# Analysis functions shared by the interface and optional command-line workflow.
execute_sql_file <- function(con,path) {
  lines<-readLines(path,warn=FALSE);text<-paste(lines[!grepl('^\\s*--',lines)],collapse='\n')
  for (sql in strsplit(text,';',fixed=TRUE)[[1]]) if(nzchar(trimws(sql))) DBI::dbExecute(con,sql)
}

business_queries <- function(root='.') {
  text<-paste(readLines(file.path(root,'sql/03_questions.sql'),warn=FALSE),collapse='\n')
  blocks<-strsplit(text,'(?m)^-- [0-9]+[.] ',perl=TRUE)[[1]][-1]
  lapply(blocks,function(block) {
    lines<-strsplit(block,'\n',fixed=TRUE)[[1]]
    list(title=lines[1],sql=trimws(paste(lines[-1],collapse='\n')))
  })
}

read_query <- function(database,sql,limit=1000L) {
  sql<-trimws(sql)
  # Read-only connection and query_only also protect SELECTs containing functions/CTEs.
  leading<-sub('^(\\s|--[^\n]*(\n|$)|/\\*.*?\\*/)*','',sql,perl=TRUE)
  if (!grepl('^(SELECT|WITH|EXPLAIN)\\b',leading,ignore.case=TRUE)) stop('Use one SELECT, WITH or EXPLAIN query.')
  con<-DBI::dbConnect(RSQLite::SQLite(),database,flags=RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con),add=TRUE);DBI::dbExecute(con,'PRAGMA query_only=ON')
  result<-withCallingHandlers(DBI::dbSendQuery(con,sql),warning=function(w) stop(conditionMessage(w)))
  on.exit(DBI::dbClearResult(result),add=TRUE,after=FALSE)
  values<-DBI::dbFetch(result,n=as.integer(limit)+1L)
  list(data=head(values,limit),truncated=nrow(values)>limit)
}

check_database <- function(con) {
  checks<-c(
    subscriptions_after_signup="SELECT COUNT(*) n FROM subscriptions s JOIN users u USING(user_id) WHERE s.start_date<u.signup_date OR s.start_date>(SELECT as_of FROM settings)",
    payments_within_access="SELECT COUNT(*) n FROM payments p JOIN subscriptions s USING(subscription_id) WHERE p.payment_date<s.start_date OR (p.status='succeeded' AND p.payment_date>=s.end_date)",
    payments_within_observation="SELECT COUNT(*) n FROM payments WHERE payment_date>(SELECT as_of FROM settings)",
    activity_within_observation="SELECT COUNT(*) n FROM activity_events e JOIN users u USING(user_id) WHERE e.event_date<u.signup_date OR e.event_date>(SELECT as_of FROM settings)",
    payments_match_plan_price="SELECT COUNT(*) n FROM payments p JOIN subscriptions s USING(subscription_id) JOIN plans pl USING(plan_id) WHERE p.amount_cents<>pl.price_cents",
    every_user_has_signup_activity="SELECT COUNT(*) n FROM users u WHERE NOT EXISTS(SELECT 1 FROM activity_events e WHERE e.user_id=u.user_id AND e.event_date=u.signup_date)",
    observed_retention_is_valid="SELECT COUNT(*) n FROM cohort_retention WHERE retention_rate<0 OR retention_rate>1 OR (observed=0 AND retention_rate IS NOT NULL)")
  quality<-data.frame(check=names(checks),violations=vapply(checks,function(q)as.integer(DBI::dbGetQuery(con,q)$n),integer(1)))
  if (nrow(DBI::dbGetQuery(con,'PRAGMA foreign_key_check')) || DBI::dbGetQuery(con,'PRAGMA integrity_check')[[1]]!='ok' || any(quality$violations)) stop('Source integrity checks failed: ',paste(quality$check[quality$violations>0],collapse=', '),'. The current analysis was retained.')
  totals<-c(DBI::dbGetQuery(con,"SELECT COALESCE(SUM(amount_cents),0) n FROM payments WHERE status='succeeded'")$n,
    DBI::dbGetQuery(con,'SELECT SUM(revenue_cents) n FROM monthly_metrics')$n,
    DBI::dbGetQuery(con,'SELECT SUM(lifetime_cash_cents) n FROM user_metrics')$n)
  if (length(unique(totals))!=1) stop('Cash reconciliation failed.')
  quality
}

html_escape <- function(x) {
  x<-gsub('&','&amp;',as.character(x),fixed=TRUE);x<-gsub('<','&lt;',x,fixed=TRUE)
  x<-gsub('>','&gt;',x,fixed=TRUE);gsub('"','&quot;',x,fixed=TRUE)
}

html_table <- function(x) {
  if (!nrow(x)) return('<p>No matching rows.</p>')
  cells<-lapply(x,function(v)ifelse(is.na(v),'',html_escape(v)))
  rows<-vapply(seq_len(nrow(x)),function(i)paste0('<tr>',paste0('<td>',vapply(cells,`[`,character(1),i),'</td>',collapse=''),'</tr>'),character(1))
  paste0('<div class="scroll"><table><thead><tr>',paste0('<th>',html_escape(names(x)),'</th>',collapse=''),
    '</tr></thead><tbody>',paste(rows,collapse=''),'</tbody></table></div>')
}

interpret_results <- function(users,months,cohorts,channel,mix) {
  first<-months[1,];last<-months[nrow(months),]
  high<-channel[which.max(channel$conversion),];low<-channel[which.min(channel$conversion),]
  renewals<-mix[mix$payment_type=='Renewal',]
  renewal_cash<-if(nrow(renewals))renewals$cash_eur else 0
  renewal_share<-if(nrow(renewals))renewals$cash_share else 0
  first_pay<-mix[mix$payment_type=='First payment',]
  first_cash<-if(nrow(first_pay))first_pay$cash_eur else 0
  jan<-cohorts[cohorts$cohort_month=='2025-01' & cohorts$month_index==1,]
  list(
    list(title='Growth and conversion are different questions',
      evidence=sprintf('Registrations changed from %s to %s between %s and %s. Mature 7-day conversion changed from %.2f%% to %.2f%%: %+.2f percentage points.',first$registrations,last$registrations,first$month,last$month,100*first$conversion_7d,100*last$conversion_7d,100*(last$conversion_7d-first$conversion_7d)),
      meaning='Registrations measure acquisition volume. Conversion measures how often sufficiently observed new users make a first successful payment. More registrations do not automatically mean a stronger conversion rate.',
      next_step='Compare conversion within signup month, country and acquisition channel. Use counts together with rates; do not average channel percentages without their denominators.',
      boundary='The monthly endpoints are a descriptive comparison, not a trend-significance test or a causal result.'),
    list(title='Separate cash from new-customer acquisition',
      evidence=sprintf('First successful payments contributed EUR %.2f; subsequent successful payments contributed EUR %.2f (%.2f%% of collected cash). Monthly cash changed from EUR %.2f to EUR %.2f.',first_cash,renewal_cash,100*renewal_share,first$revenue_eur,last$revenue_eur),
      meaning='Cash includes payments from the accumulated audience. The first-versus-renewal split shows why total cash and new-user conversion need not move together. It does not by itself attribute the entire monthly change to renewals.',
      next_step='Use SQL question 12 to verify the split. To explain monthly growth further, break first-payment and renewal cash down by payment month.',
      boundary='Cash excludes failed attempts and is not profit, MRR, accrual revenue or a renewal probability.'),
    list(title='Channel differences need context',
      evidence=sprintf('%s converted %s of %s eligible users (%.2f%%), versus %s of %s for %s (%.2f%%). The difference is %.2f percentage points.',high$channel,high$converted_users,high$eligible_users,100*high$conversion,low$converted_users,low$eligible_users,low$channel,100*low$conversion,100*(high$conversion-low$conversion)),
      meaning='This describes the acquisition mix in the current dataset. It identifies a comparison worth investigating; it does not establish that shifting budget to the highest-rate channel will improve outcomes.',
      next_step='Inspect country and signup-month composition and obtain acquisition spend before considering budget changes.',
      boundary='Channel assignment is not randomized, and channel quality differs by construction in the generator. Individual 95% intervals are not a multiple-comparison or causal test.'),
    list(title='Read retention as return-to-content activity',
      evidence=if(nrow(jan))sprintf('%s of %s January registrants returned in February: %.2f%% calendar-month M1 activity retention.',jan$active_users,jan$cohort_size,100*jan$retention_rate) else 'Inspect the observed cohort rows; there is no January M1 cell in this dataset.',
      meaning='The cohort denominator includes everyone who registered in that month, including non-payers. A return event means at least one content view; it says nothing about daily frequency or paid renewal.',
      next_step='Compare cohorts at the same month offset. On real data, validate events and compare users with similar follow-up before recommending engagement changes.',
      boundary='M0 is 100% because of signup-day events. Late-month signups have shorter first-month exposure. Unobserved future cells are NULL, not zero.')
  )
}

write_report <- function(snapshot,root) {
  m<-snapshot$manifest;k<-snapshot$kpis;path<-file.path(snapshot$path,'results')
  image<-function(name) paste0('<img alt="',name,' chart" src="data:image/png;base64,',base64enc::base64encode(file.path(path,paste0(name,'.png'))),'">')
  queries<-business_queries(root)
  query_html<-vapply(seq_along(queries),function(i) {
    q<-queries[[i]];r<-read_query(snapshot$database,q$sql,10L)
    paste0('<details><summary>',i,'. ',html_escape(q$title),'</summary><pre>',html_escape(q$sql),'</pre>',
      html_table(r$data),if(r$truncated)'<p>First 10 rows shown. Run the query in the analyzer for more results.</p>' else '', '</details>')
  },character(1))
  html<-paste0('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Subscription Analytics — Case Study</title><style>body{font:16px/1.65 system-ui,sans-serif;color:#18283d;background:#f3f6fa;margin:0}main{max-width:1080px;margin:auto;padding:40px 24px}h1{font-size:38px;line-height:1.15}h2{margin-top:36px}small,.muted{color:#52647b}.cards{display:flex;gap:16px;flex-wrap:wrap}.card{background:white;border:1px solid #dde5ef;border-radius:12px;padding:20px;flex:1;min-width:180px}.value{font-size:30px;font-weight:700}img{width:100%;background:white;border:1px solid #dde5ef;border-radius:12px;margin:12px 0}table{border-collapse:collapse;width:100%;font-size:14px}td,th{text-align:left;padding:8px 12px;border-bottom:1px solid #dce5ef}th{background:#eaf0f8}.scroll{overflow:auto}details{background:white;border:1px solid #dce5ef;padding:16px;border-radius:10px;margin:12px 0}summary{cursor:pointer;font-weight:600}pre{overflow:auto;padding:14px;background:#10243a;color:#edf5ff;border-radius:8px;font-size:13px}li{margin:8px 0}</style></head><body><main>',
    '<small>SQL · R · POWER BI / SYNTHETIC CASE STUDY</small><h1>Does user growth translate into paying customers?</h1>',
    '<p>Acquisition quality, collected cash and calendar-month activity retention for a fictional content subscription service.</p>',
    '<p class="muted">Dataset: ',html_escape(m$dataset_id),' · Observation: ',m$observation_start,' to ',m$observation_end,' · EUR</p>',
    '<div class="cards"><div class="card">Registered users<div class="value">',format(k$users,big.mark=','),'</div></div>',
    '<div class="card">7-day conversion<div class="value">',sprintf('%.2f%%',100*k$conversion),'</div><small>',k$converted,' / ',k$eligible,' fully observed users</small></div>',
    '<div class="card">Collected cash<div class="value">€',format(k$cash,big.mark=',',nsmall=2),'</div><small>Successful payments, including renewals</small></div></div>',
    '<h2>Findings</h2><ol>',paste0('<li>',html_escape(snapshot$findings),'</li>',collapse=''),'</ol>',
    '<h2>Interpretation and next steps</h2>',paste(vapply(snapshot$interpretation,function(x)paste0('<section><h3>',html_escape(x$title),'</h3><p><strong>Evidence.</strong> ',html_escape(x$evidence),'</p><p>',html_escape(x$meaning),'</p><p><strong>Next check.</strong> ',html_escape(x$next_step),'</p><p class="muted"><strong>Boundary.</strong> ',html_escape(x$boundary),'</p></section>'),character(1)),collapse=''),
    '<h2>Cash by payment month</h2>',image('cash'),'<h2>7-day conversion by acquisition channel</h2>',image('conversion'),
    '<h2>Return-to-content activity</h2>',image('retention'),
    '<h2>Recommended next checks</h2><ul><li>Compare channels within country and signup month before recommending acquisition changes.</li><li>Separate first payments from renewals when explaining the cash trend.</li><li>Obtain acquisition spend, refunds and costs before estimating profit, CAC or LTV.</li></ul>',
    '<h2>SQL evidence</h2><p>These are saved query results for this dataset. Use the local analyzer to edit and execute the SQL.</p>',paste(query_html,collapse=''),
    '<h2>Metric boundaries</h2><ul><li>Conversion includes signup day and the following six dates. Users without all seven dates are excluded.</li><li>Cash excludes failed attempts. It is not profit, MRR or accrual revenue.</li><li>Retention means at least one content view in a calendar month, not paid subscription renewal.</li><li>M0 is 100% because every synthetic user has a signup-day event. Grey future cells are unobserved, not zero.</li><li>Channel error bars are individual 95% score intervals. Differences are observational and reflect generation assumptions.</li></ul>',
    '<h2>Power BI</h2><p>The analyzer can export a portable Power BI project with this scenario embedded: extract the ZIP, open the PBIP and click Refresh once. The repository also retains a working CSV-linked Desktop project. This HTML report is generated by R.</p>',
    '<p class="muted">All data is synthetic. Results describe this scenario and are not commercial achievements.</p></main></body></html>')
  writeLines(html,file.path(path,'report.html'),useBytes=TRUE)
}

analyse_dataset <- function(imported,root='.') {
  root<-normalizePath(root);folder<-tempfile('subscription-analysis-');dir.create(folder)
  success<-FALSE;on.exit(if(!success)unlink(folder,recursive=TRUE),add=TRUE)
  for (p in c('data/source','data/processed','results')) dir.create(file.path(folder,p),recursive=TRUE)
  for (table in source_tables) if(!file.copy(file.path(imported$path,paste0(table,'.csv')),file.path(folder,'data/source'))) stop('Could not stage source data.')
  jsonlite::write_json(imported$manifest,file.path(folder,'data/manifest.json'),pretty=TRUE,auto_unbox=TRUE)
  database<-file.path(folder,'data/subscription_analytics.sqlite')
  con<-DBI::dbConnect(RSQLite::SQLite(),database)
  connected<-TRUE;on.exit(if(connected)DBI::dbDisconnect(con),add=TRUE)
  execute_sql_file(con,file.path(root,'sql/01_schema.sql'))
  DBI::dbWithTransaction(con,{
    DBI::dbAppendTable(con,'settings',data.frame(as_of=imported$manifest$observation_end))
    for (table in source_tables) DBI::dbAppendTable(con,table,imported$data[[table]])
  })
  execute_sql_file(con,file.path(root,'sql/02_views.sql'))
  quality<-check_database(con)
  users<-DBI::dbGetQuery(con,'SELECT * FROM user_metrics ORDER BY user_id')
  months<-DBI::dbGetQuery(con,'SELECT * FROM monthly_metrics ORDER BY month')
  cohorts<-DBI::dbGetQuery(con,'SELECT * FROM cohort_retention ORDER BY cohort_month,month_index')
  payments<-DBI::dbGetQuery(con,"SELECT p.*,s.user_id,pl.plan_name,substr(p.payment_date,1,7) payment_month FROM payments p JOIN subscriptions s USING(subscription_id) JOIN plans pl USING(plan_id) ORDER BY payment_id")
  tables<-list(user_metrics=users,monthly_metrics=months,cohort_retention=cohorts,payment_facts=payments)
  for (name in names(tables)) write.csv(tables[[name]],file.path(folder,'data/processed',paste0(name,'.csv')),row.names=FALSE,na='')
  write.csv(quality,file.path(folder,'results/data_quality.csv'),row.names=FALSE)
  channel<-DBI::dbGetQuery(con,'SELECT channel,COUNT(*) eligible_users,SUM(converted_7d) converted_users,1.0*SUM(converted_7d)/COUNT(*) conversion FROM user_metrics WHERE eligible_7d=1 GROUP BY channel')
  if(!nrow(channel)) stop('No users have a complete seven-date conversion window.')
  intervals<-t(vapply(seq_len(nrow(channel)),function(i)suppressWarnings(stats::prop.test(channel$converted_users[i],channel$eligible_users[i],correct=FALSE)$conf.int),numeric(2)))
  channel$ci_low<-intervals[,1];channel$ci_high<-intervals[,2]
  write.csv(channel,file.path(folder,'results/channel_conversion.csv'),row.names=FALSE)
  theme<-ggplot2::theme_minimal(base_size=12)+ggplot2::theme(panel.grid.minor=ggplot2::element_blank(),plot.title=ggplot2::element_text(face='bold'))
  cash<-ggplot2::ggplot(months,ggplot2::aes(x=as.Date(paste0(month,'-01')),y=revenue_eur))+
    ggplot2::geom_line(colour='#2463a8',linewidth=1)+ggplot2::geom_point(colour='#2463a8',size=2)+
    ggplot2::labs(title='Collected cash by payment month',subtitle='Synthetic data | successful payments, including renewals',x=NULL,y='EUR')+theme
  conversion<-ggplot2::ggplot(channel,ggplot2::aes(x=reorder(channel,conversion),y=conversion))+
    ggplot2::geom_col(fill='#2463a8',width=.6)+ggplot2::geom_errorbar(ggplot2::aes(ymin=ci_low,ymax=ci_high),width=.15)+ggplot2::coord_flip()+
    ggplot2::scale_y_continuous(labels=function(x)paste0(round(x*100),'%'))+
    ggplot2::labs(title='7-day conversion by acquisition channel',subtitle='Complete observation windows | individual 95% score intervals',x=NULL,y='Converted / eligible users')+theme
  retention<-ggplot2::ggplot(cohorts,ggplot2::aes(x=month_index,y=factor(cohort_month,levels=rev(unique(cohort_month))),fill=retention_rate))+
    ggplot2::geom_tile(colour='white')+ggplot2::geom_text(ggplot2::aes(label=ifelse(observed==0,'',paste0(round(retention_rate*100),'%'))),size=3)+
    ggplot2::scale_fill_gradient(low='#edf3fb',high='#2463a8',na.value='#e1e6ed',limits=c(0,1))+
    ggplot2::scale_x_continuous(breaks=0:11)+ggplot2::labs(title='Calendar-month activity retention',subtitle='Signup cohorts | grey cells are not observed yet',x='Months since signup month',y=NULL,fill='Rate')+theme
  for(name in c('cash','conversion','retention')) ggplot2::ggsave(file.path(folder,'results',paste0(name,'.png')),get(name),width=10,height=if(name=='retention')6 else 4.5,dpi=140,bg='white')
  eligible<-users[users$eligible_7d==1,];first<-months[1,];last<-months[nrow(months),]
  kpis<-list(users=nrow(users),eligible=nrow(eligible),converted=sum(eligible$converted_7d),
    conversion=if(nrow(eligible))mean(eligible$converted_7d) else NA_real_,cash=sum(months$revenue_cents)/100)
  high<-channel[which.max(channel$conversion),];low<-channel[which.min(channel$conversion),]
  jan<-cohorts[cohorts$cohort_month=='2025-01' & cohorts$month_index==1,]
  findings<-c(
    sprintf('%s to %s: registrations %s → %s; mature 7-day conversion %.2f%% → %.2f%% (%+.2f percentage points).',first$month,last$month,first$registrations,last$registrations,100*first$conversion_7d,100*last$conversion_7d,100*(last$conversion_7d-first$conversion_7d)),
    sprintf('Collected cash changed from EUR %.2f in %s to EUR %.2f in %s. This includes renewals, so it does not measure new-user conversion alone.',first$revenue_eur,first$month,last$revenue_eur,last$month),
    sprintf('%s has the highest observed channel conversion (%.2f%%); %s has the lowest (%.2f%%). These are scenario-specific associations, not causal marketing effects.',high$channel,100*high$conversion,low$channel,100*low$conversion),
    if(nrow(jan))sprintf('%.2f%% of January registrants returned to view content in February. This measures activity, not paid renewal.',100*jan$retention_rate) else 'The dataset has no January cohort; inspect the observed cohort rows.')
  mix<-DBI::dbGetQuery(con,business_queries(root)[[12]]$sql)
  write.csv(mix,file.path(folder,'results/payment_mix.csv'),row.names=FALSE)
  interpretation<-interpret_results(users,months,cohorts,channel,mix)
  jsonlite::write_json(interpretation,file.path(folder,'results/interpretation.json'),pretty=TRUE,auto_unbox=TRUE)
  write.csv(data.frame(metric=names(kpis),value=unlist(kpis)),file.path(folder,'results/kpis.csv'),row.names=FALSE)
  writeLines(c('# Subscription Analytics — findings','',paste('Dataset:',imported$manifest$dataset_id),'',
    '**Synthetic scenario; not real business performance.**','',paste0('- ',findings),'',
    unlist(lapply(interpretation,function(x)c(paste('##',x$title),'',paste('**Evidence.**',x$evidence),'',paste('**Interpretation.**',x$meaning),'',paste('**Next check.**',x$next_step),'',paste('**Boundary.**',x$boundary),''))),
    '## Next checks','- Compare channels within country and signup month.',
    '- Separate first payments from renewals.','- Obtain spend, refunds and costs before estimating CAC, LTV or profit.'),file.path(folder,'results/findings.md'),useBytes=TRUE)
  DBI::dbDisconnect(con);connected<-FALSE
  snapshot<-list(path=folder,database=database,manifest=imported$manifest,kpis=kpis,findings=findings,interpretation=interpretation,quality=quality)
  write_report(snapshot,root);success<-TRUE;snapshot
}

load_analysis <- function(root='.') {
  root<-normalizePath(root);checked<-read_sources(file.path(root,'data/source'),file.path(root,'data/manifest.json'))
  k<-read.csv(file.path(root,'results/kpis.csv'));values<-as.list(setNames(k$value,k$metric))
  list(path=root,database=file.path(root,'data/subscription_analytics.sqlite'),manifest=checked$manifest,
    kpis=values,findings=sub('^- ','',grep('^- ',readLines(file.path(root,'results/findings.md'),warn=FALSE),value=TRUE))[1:4],
    interpretation=jsonlite::fromJSON(file.path(root,'results/interpretation.json'),simplifyVector=FALSE),
    quality=read.csv(file.path(root,'results/data_quality.csv')))
}

export_powerbi_data <- function(snapshot,destination) {
  # A browser download transfers the current session's CSVs to the visitor's PC.
  destination<-file.path(normalizePath(dirname(destination),mustWork=TRUE),basename(destination))
  stage<-tempfile('powerbi-export-');dir.create(stage)
  on.exit(unlink(stage,recursive=TRUE),add=TRUE)
  tables<-c('user_metrics','payment_facts','cohort_retention','monthly_metrics')
  for(table in tables) {
    source<-file.path(snapshot$path,'data/processed',paste0(table,'.csv'))
    if(!file.copy(source,stage))stop('Could not prepare Power BI data: ',table)
  }
  info<-list(dataset_id=snapshot$manifest$dataset_id,seed=snapshot$manifest$seed,
    currency='EUR',kpis=snapshot$kpis,
    files=setNames(lapply(tables,function(table) {
      file<-file.path(stage,paste0(table,'.csv'))
      list(rows=nrow(read.csv(file)),sha256=digest::digest(file=file,algo='sha256',serialize=FALSE))
    }),paste0(tables,'.csv')))
  jsonlite::write_json(info,file.path(stage,'dataset-info.json'),pretty=TRUE,auto_unbox=TRUE)
  writeLines(c('POWER BI DATA — CURRENT ANALYZER SESSION',paste('Dataset:',info$dataset_id),
    '', '1. Extract these CSVs into a folder on YOUR computer.',
    '2. In Power BI Desktop set DataFolder to the absolute path of that folder.',
    '3. Apply changes and click Home > Refresh.',
    'For later datasets, replace the CSVs in the same local folder and refresh again.',
    '', 'The three model inputs are user_metrics.csv, payment_facts.csv and cohort_retention.csv.',
    'monthly_metrics.csv is an additional analytical export. dataset-info.json records the scenario.',
    sprintf('Expected unfiltered values: %s users; %.2f%% conversion; EUR %.2f collected cash.',
      snapshot$kpis$users,100*snapshot$kpis$conversion,snapshot$kpis$cash),
    '', 'This is prepared Power BI data, not a generator source bundle.'),file.path(stage,'README.txt'))
  zip::zipr(destination,files=list.files(stage),root=stage,mode='mirror')
}

export_powerbi_project <- function(snapshot,destination,root='.') {
  # Freeze the current scenario inside an independent native Power BI project.
  destination<-file.path(normalizePath(dirname(destination),mustWork=TRUE),basename(destination))
  stage<-tempfile('powerbi-project-');dir.create(stage)
  on.exit(unlink(stage,recursive=TRUE),add=TRUE)
  parts<-c('SubscriptionAnalytics.pbip','SubscriptionAnalytics.Report','SubscriptionAnalytics.SemanticModel','measures.dax')
  if(!all(file.copy(file.path(root,'powerbi',parts),stage,recursive=TRUE)))stop('Could not copy the Power BI project template.')
  for(part in c('SubscriptionAnalytics.Report','SubscriptionAnalytics.SemanticModel'))unlink(file.path(stage,part,'.pbi'),recursive=TRUE)
  model_path<-file.path(stage,'SubscriptionAnalytics.SemanticModel/model.bim')
  model<-jsonlite::fromJSON(model_path,simplifyVector=FALSE)
  inputs<-c(Users='user_metrics.csv',Payments='payment_facts.csv',Cohorts='cohort_retention.csv')
  for(i in seq_along(model$model$tables)) {
    table<-model$model$tables[[i]];file<-unname(inputs[table$name])
    if(length(file)!=1 || is.na(file))stop('Unexpected Power BI table.')
    encoded<-base64enc::base64encode(file.path(snapshot$path,'data/processed',file))
    starts<-seq.int(1L,nchar(encoded),by=16000L)
    chunks<-substring(encoded,starts,pmin(starts+15999L,nchar(encoded)))
    expression<-unlist(table$partitions[[1]]$source$expression,use.names=FALSE)
    index<-grep('Source = Csv.Document',expression,fixed=TRUE)
    if(length(index)!=1)stop('Unsupported Power Query template.')
    replacement<-c('    EmbeddedCsv = Text.Combine({',
      paste0('        "',chunks,'"',ifelse(seq_along(chunks)<length(chunks),',','')),
      '    }),',
      '    Source = Csv.Document(Binary.FromText(EmbeddedCsv, BinaryEncoding.Base64), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),')
    table$partitions[[1]]$source$expression<-as.list(append(expression[-index],replacement,after=index-1L))
    model$model$tables[[i]]<-table
  }
  model$model$expressions<-Filter(function(x)!identical(x$name,'DataFolder'),model$model$expressions)
  jsonlite::write_json(model,model_path,pretty=TRUE,auto_unbox=TRUE,null='null',digits=NA)
  dir.create(file.path(stage,'data'))
  tables<-c('user_metrics','payment_facts','cohort_retention','monthly_metrics')
  for(table in tables)file.copy(file.path(snapshot$path,'data/processed',paste0(table,'.csv')),file.path(stage,'data'))
  jsonlite::write_json(list(dataset_id=snapshot$manifest$dataset_id,seed=snapshot$manifest$seed,
    kpis=snapshot$kpis,data_mode='embedded Power Query snapshot',requires_local_data_folder=FALSE),
    file.path(stage,'dataset-info.json'),pretty=TRUE,auto_unbox=TRUE)
  file.copy(file.path(snapshot$path,'results/report.html'),file.path(stage,'case-study.html'))
  writeLines(c('# Portable Power BI case study','',paste('Dataset:',snapshot$manifest$dataset_id),'',
    '1. Extract the entire ZIP to a folder on your computer.',
    '2. Open SubscriptionAnalytics.pbip in Power BI Desktop.',
    '3. Click Home > Refresh once to load the embedded scenario into the model.',
    '4. Explore Overview and Retention. You may then save a local PBIX copy.',
    '', 'No DataFolder, repository checkout, internet data source or BAT/CMD launcher is required.',
    'The current CSV bytes are embedded in the model Power Query definitions. The data/ folder is a readable copy for inspection.',
    'Editing those CSV copies does not change this frozen report. Export another project to capture a different scenario.',
    '',sprintf('Unfiltered headline values: %s users; %.2f%% conversion; EUR %.2f collected cash.',
      snapshot$kpis$users,100*snapshot$kpis$conversion,snapshot$kpis$cash),
    '', 'The package is a PBIP source project, not a pre-refreshed PBIX. Its first Desktop refresh is required.',
    'Native Power BI Desktop refresh and rendering must be verified locally. case-study.html provides an independent R-generated preview.'),
    file.path(stage,'OPEN-ME.md'),useBytes=TRUE)
  zip::zipr(destination,files=list.files(stage),root=stage,mode='mirror')
}

save_analysis <- function(snapshot,root='.') {
  # Explicit publication only. Roll back the previous working files on a copy error.
  root<-normalizePath(root);if(normalizePath(snapshot$path)==root)return(invisible(root))
  items<-c('data/source','data/processed','data/manifest.json','data/subscription_analytics.sqlite','results')
  backup<-tempfile('analysis-backup-');dir.create(backup)
  on.exit(unlink(backup,recursive=TRUE),add=TRUE)
  for (i in seq_along(items)) {
    src<-file.path(root,items[i]);dest<-file.path(backup,as.character(i));dir.create(dest)
    if(file.exists(src) && !file.copy(src,dest,recursive=TRUE)) stop('Could not back up working analysis.')
  }
  tryCatch({
    for(item in items) {
      destination<-file.path(root,item);unlink(destination,recursive=TRUE)
      dir.create(dirname(destination),recursive=TRUE,showWarnings=FALSE)
      if(!file.copy(file.path(snapshot$path,item),dirname(destination),recursive=TRUE))stop('Could not save ',item,'.')
    }
  },error=function(e) {
    for(i in seq_along(items)) {
      destination<-file.path(root,items[i]);unlink(destination,recursive=TRUE)
      previous<-list.files(file.path(backup,as.character(i)),full.names=TRUE)
      if(length(previous))file.copy(previous,dirname(destination),recursive=TRUE)
    }
    stop('Save failed; restoration of previous working files was attempted. ',conditionMessage(e))
  })
  invisible(root)
}

if (sys.nframe()==0L) {
  args<-commandArgs(trailingOnly=FALSE);script<-sub('^--file=','',args[grepl('^--file=',args)])
  if(length(script))setwd(dirname(normalizePath(script[1])))
  source('import_data.R')
  checked<-read_sources('data/source','data/manifest.json')
  imported<-list(path=normalizePath('data/source'),data=checked$data,manifest=checked$manifest)
  snapshot<-analyse_dataset(imported,getwd());save_analysis(snapshot,getwd());unlink(snapshot$path,recursive=TRUE)
  message('Analysis rebuilt. Open results/report.html; refresh Power BI.')
}
