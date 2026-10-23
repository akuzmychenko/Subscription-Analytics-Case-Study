library(shiny)
options(shiny.maxRequestSize=30*1024^2)
project_dir<-normalizePath(getwd())
style<-'body{background:#f2f5fa;color:#20334a;font-family:system-ui,-apple-system,Segoe UI,sans-serif;font-size:16px;line-height:1.65}.container-fluid{max-width:1240px;padding:28px 30px}.hero{padding:12px 0 22px}.eyebrow{font-size:12px;font-weight:700;color:#2763a1;letter-spacing:2px}.hero h1{font-weight:750;letter-spacing:-1px;font-size:38px}.hero p{font-size:17px;color:#52647b;max-width:850px}.well{background:#fff;border:1px solid #dce5ef;border-radius:14px;box-shadow:none;padding:22px}.panel-card{background:#fff;border:1px solid #dce5ef;border-radius:14px;padding:22px;margin:18px 0}.panel-card h3{margin-top:0;font-size:21px;font-weight:650}.metric-grid{display:flex;gap:14px;flex-wrap:wrap;margin:0 0 22px}.metric-card{flex:1;min-width:180px;background:#fff;border:1px solid #dce5ef;padding:20px;border-radius:14px}.metric-value{font-size:31px;font-weight:750;line-height:1.3;margin:6px 0}.metric-label{color:#52647b;font-weight:600}.metric-note,.helper{color:#62738a;font-size:13px;line-height:1.5}.btn-primary{background:#2463a8;border-color:#2463a8}.full-button{width:100%;margin:5px 0;padding:11px}.status{padding:12px 14px;background:#eaf2fc;border-radius:9px;overflow-wrap:anywhere;margin:14px 0}.nav-tabs{border-bottom:1px solid #dce5ef}.nav-tabs>li>a{font-weight:600}.nav-tabs>li.active>a{background:#fff;border-color:#dce5ef;border-bottom-color:#fff}textarea{font-family:ui-monospace,Consolas,monospace!important;font-size:14px!important;line-height:1.6}.scroll{overflow:auto;max-height:560px}.scroll th{position:sticky;top:0;background:#edf3fa}.panel-card section{padding:14px 0;border-top:1px solid #e3eaf3}.panel-card h4{font-weight:650;font-size:18px;margin-bottom:12px}table{font-size:13px}.footer{color:#62738a;font-size:12px;padding:20px 0}.shiny-image-output{height:auto!important;min-height:0}.shiny-image-output img{display:block;width:100%;max-width:100%;height:auto}@media(max-width:767px){.container-fluid{padding:18px 14px}.hero h1{font-size:29px}.panel-card{padding:14px}.metric-card{min-width:140px}}'

source('import_data.R');source('analysis.R')
queries<-business_queries(project_dir)
query_notes<-c(
  "Compare registration volume by channel. A larger count does not by itself imply better conversion or lower acquisition cost.",
  "Compare successful cash collected by plan. Higher cash can reflect price, payer count or repeated payments; it is not plan profitability.",
  "These users have no observed successful payment. Recent registrations may have incomplete follow-up, so this is not a list of proven acquisition failures.",
  "The denominator contains only complete seven-date windows. A conversion_rate of 0.25 means 25%; compare eligible counts as well as rates.",
  "The average includes all users, including those with zero cash. This identifies high-cash observations, not causal drivers or profitable customers.",
  "Payment numbers are calculated after excluding failed attempts. Each user starts at 1; LAG shows the previous successful payment date.",
  "Total-cash rank reflects audience size, prices and repeat payments. It does not rank causal marketing effectiveness or return on advertising spend.",
  "Cash belongs to payment month, while conversion belongs to signup month. The first or zero-denominator month-over-month value is NULL, not zero growth.",
  "Compare cohorts at the same month_index. Observed zero means no return events; NULL means the period was not observed.",
  "The denominator is users who paid at least once. Paying twice is not a renewal probability: users have different follow-up and renewal opportunities.",
  "Attempt counts differ from paying-user counts. Failed attempted amounts are excluded from cash and are not automatically lost revenue.",
  "Each payer has one first successful payment; later successful payments are renewals in this model. cash_share is a share of money, not a share of users who renewed."
)
ui<-fluidPage(tags$head(tags$style(HTML(style))),
  div(class='hero',div(class='eyebrow','SUBSCRIPTION DATA / ANALYZER'),h1('From source data to a clear business case'),
      p('Explore the included case, run real SQL queries, or import another scenario from the separate generator.')),
  uiOutput('dataset_status'),uiOutput('cards'),
  tabsetPanel(id='page',
    tabPanel('Overview',
      div(class='panel-card',h3('Business question'),p('Are more registrations translating into paying users and collected cash? How do acquisition quality and return activity differ?'),
          uiOutput('findings'),downloadButton('report_download','Download HTML case study')),
      div(class='panel-card',h3('Collected cash by month'),imageOutput('cash_plot',height='auto')),
      div(class='panel-card',h3('Conversion by acquisition channel'),imageOutput('conversion_plot',height='auto')),
      div(class='panel-card',h3('Activity retention'),imageOutput('retention_plot',height='auto')),
      div(class='panel-card',h3('Interpretation and next steps'),uiOutput('interpretation')),
      div(class='panel-card',h3('Reading the metrics'),
          tags$ul(tags$li('Conversion: first successful payment on signup day or the following six dates; incomplete windows excluded.'),
            tags$li('Cash: successful payments, including renewals. It is not profit or MRR.'),
            tags$li('Retention: return to content in a calendar month. It is not paid renewal.'),
            tags$li('Future cohort cells are missing, not zero. Channel comparisons are observational.')))),
    tabPanel('SQL',
      div(class='panel-card',h3('Ask the database'),
          selectInput('question','Choose a business question',choices=setNames(seq_along(queries),vapply(queries,function(q)q$title,character(1)))),
          uiOutput('query_explanation'),
          textAreaInput('sql','SQL query',value=queries[[1]]$sql,rows=9,width='100%'),
          actionButton('run_query','Run query',class='btn-primary'),
          p(class='helper','The query runs against the dataset shown above. Read-only mode preserves the source data. Up to 1,000 rows are displayed and exported.'),
          uiOutput('sql_status'),div(class='scroll',tableOutput('sql_result')),uiOutput('sql_download_control')),
      div(class='panel-card',h3('Available tables and views'),
          p('Tables: users, plans, subscriptions, payments, activity_events, settings.'),
          p('Views: user_metrics, monthly_metrics, cohort_retention.'),
          p(class='helper','Definitions: sql/01_schema.sql and sql/02_views.sql. The twelve presets come from sql/03_questions.sql.'))),
    tabPanel('Import data',
      fluidRow(column(6,div(class='panel-card',h3('1. Load another scenario'),
        fileInput('bundle','Dataset ZIP from the generator',accept='.zip'),
        actionButton('analyze','Run analysis',class='btn-primary'),
        p(class='helper','The source ZIP is checked before the database and report are rebuilt. A failed import retains the current view.'),
        uiOutput('import_status'),tags$hr(),actionButton('baseline','Load presentation dataset'),
        p(class='helper','Restores the original 4,890-user case in this session. It does not overwrite saved working files.'))),
        column(6,div(class='panel-card',h3('2. Export a ready Power BI project'),
          p('Download the current scenario to your computer, whether this app runs locally, in Codespaces or on a hosting service.'),
          downloadButton('powerbi_download','Download Power BI project ZIP',class='btn-primary full-button'),
          downloadButton('csvs_download','Download CSVs only',class='full-button'),
          p(class='helper','The project ZIP contains the report, measures and current scenario embedded in its model. No DataFolder setup or commit is needed.'),
          tags$hr(),h4('Open Power BI Desktop'),
          tags$ol(tags$li('Extract the entire project ZIP into a new folder on your computer.'),tags$li('Open SubscriptionAnalytics.pbip from that folder.'),tags$li('Click Home → Refresh once to load the embedded data. You can then save a PBIX copy.')),
          p(class='helper','The download is a frozen snapshot of the scenario shown above. CSV-only export remains available for an existing report.'),
          tags$hr(),tags$details(tags$summary('Optional: save on the app server'),
            p('This replaces working files on the computer running R. In Codespaces or hosted deployments, that is a remote computer, not your PC.'),
            checkboxInput('confirm_save','Replace working files on the app server',FALSE),
            actionButton('save','Save on app server'),uiOutput('save_status'),
            p(class='helper','This saves server files only; it does not commit or push to GitHub. Review git status and commit manually in your own fork/branch if needed. The original baseline is retained; hosted files may be temporary.'))))),
      div(class='panel-card',h3('Source integrity checks'),tableOutput('quality')))),
  div(class='footer','SQL · R · Power BI Desktop · Synthetic data'))

server<-function(input,output,session) {
  current<-reactiveVal(load_analysis(project_dir));folders<-character()
  import_status<-reactiveVal('The saved working analysis is loaded.');save_status<-reactiveVal('No server working files changed in this session.')
  query_result<-reactiveVal(NULL);query_status<-reactiveVal('Choose a question and click Run query.')
  session$onSessionEnded(function()unlink(folders,recursive=TRUE))
  process_bundle<-function(path) {
    tryCatch(withProgress(message='Validating and analyzing the dataset',value=.1,{
      imported<-read_bundle(path);folders<<-c(folders,imported$path);incProgress(.2)
      next_analysis<-analyse_dataset(imported,project_dir);folders<<-c(folders,next_analysis$path)
      current(next_analysis);query_result(NULL);query_status('Dataset changed. Run the query again.');
      import_status('Analysis complete. Overview and SQL now use this scenario. Download Power BI project ZIP to transfer it to your computer.')
      save_status('This scenario has not replaced the app server working files.');updateCheckboxInput(session,'confirm_save',value=FALSE);incProgress(.7)
    }),error=function(e){import_status(paste('Import failed:',conditionMessage(e)));showNotification(conditionMessage(e),type='error',duration=12)})
  }
  observeEvent(input$analyze,{if(is.null(input$bundle)){import_status('Choose a dataset ZIP first.')}else process_bundle(input$bundle$datapath)})
  observeEvent(input$baseline,{process_bundle(file.path(project_dir,'data/baseline.zip'))})
  observeEvent(input$save,{
    if(!isTRUE(input$confirm_save)){save_status('Tick the server-file replacement checkbox before saving.');return()}
    tryCatch({save_analysis(current(),project_dir);save_status('Saved on the app server only. To update Power BI on your PC, download the Power BI project ZIP, extract it locally, open the PBIP and refresh once.')},
      error=function(e)save_status(conditionMessage(e)))
  })
  observeEvent(input$question,{
    i<-suppressWarnings(as.integer(input$question));if(length(i)==1 && !is.na(i) && i>=1 && i<=length(queries))updateTextAreaInput(session,'sql',value=queries[[i]]$sql)
  })
  observeEvent(input$run_query,{
    tryCatch({r<-read_query(current()$database,input$sql);query_result(r)
      query_status(paste(nrow(r$data),'rows shown.',if(r$truncated)'Result limited to the first 1,000 rows.'else'Query completed.'))},
      error=function(e){query_result(NULL);query_status(paste('Query failed:',conditionMessage(e)))})
  })
  output$dataset_status<-renderUI(div(class='status',paste('Current dataset:',current()$manifest$dataset_id,'| Seed:',current()$manifest$seed,'| Synthetic data · EUR · 2025')))
  output$cards<-renderUI({k<-current()$kpis
    card<-function(label,value,note)div(class='metric-card',div(class='metric-label',label),div(class='metric-value',value),div(class='metric-note',note))
    div(class='metric-grid',card('Registered users',format(k$users,big.mark=','),'All registrations in the scenario'),
      card('7-day conversion',sprintf('%.2f%%',100*k$conversion),paste(k$converted,'/',k$eligible,'fully observed users')),
      card('Collected cash',paste0('€',format(k$cash,big.mark=',',nsmall=2)),'Successful payments, including renewals'))
  })
  output$findings<-renderUI(tags$ol(lapply(current()$findings,tags$li)))
  output$interpretation<-renderUI(tagList(lapply(current()$interpretation,function(x)tags$section(h4(x$title),p(tags$strong('Evidence. '),x$evidence),p(x$meaning),p(tags$strong('Next check. '),x$next_step),p(class='helper',tags$strong('Boundary. '),x$boundary)))))
  for(item in c('cash','conversion','retention'))local({name<-item
    output[[paste0(name,'_plot')]]<-renderImage(list(src=file.path(current()$path,'results',paste0(name,'.png')),contentType='image/png',width='100%',alt=paste(name,'chart')),deleteFile=FALSE)
  })
  output$import_status<-renderUI(div(class='status',import_status()))
  output$save_status<-renderUI(div(class='status',save_status()))
  output$query_explanation<-renderUI({i<-suppressWarnings(as.integer(input$question));req(length(i)==1,!is.na(i),i>=1,i<=length(query_notes));p(class='helper',tags$strong('Selected preset: interpretation. '),query_notes[i])})
  output$sql_status<-renderUI(div(class='status',query_status()))
  output$sql_result<-renderTable({req(query_result());query_result()$data},digits=5,striped=TRUE)
  output$quality<-renderTable(current()$quality,striped=TRUE)
  output$sql_download_control<-renderUI({req(query_result());downloadButton('sql_download','Download shown rows as CSV')})
  output$sql_download<-downloadHandler(filename='query-result.csv',content=function(file){req(query_result());write.csv(query_result()$data,file,row.names=FALSE,na='')})
  output$powerbi_download<-downloadHandler(filename=function()paste0('powerbi-',current()$manifest$dataset_id,'.zip'),
    content=function(file)export_powerbi_project(current(),file,project_dir),contentType='application/zip')
  output$csvs_download<-downloadHandler(filename=function()paste0('csv-',current()$manifest$dataset_id,'.zip'),
    content=function(file)export_powerbi_data(current(),file),contentType='application/zip')
  output$report_download<-downloadHandler(filename=function()paste0(current()$manifest$dataset_id,'-report.html'),
    content=function(file)file.copy(file.path(current()$path,'results/report.html'),file,overwrite=TRUE),contentType='text/html')
}
shinyApp(ui,server)
