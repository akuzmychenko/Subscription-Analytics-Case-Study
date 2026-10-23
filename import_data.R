# Import functions. Run this file directly for the optional command-line workflow.
source_tables <- c('users','plans','subscriptions','payments','activity_events')
source_columns <- list(
  users=c('user_id','signup_date','country','channel'),
  plans=c('plan_id','plan_name','price_cents','billing_days'),
  subscriptions=c('subscription_id','user_id','plan_id','start_date','end_date'),
  payments=c('payment_id','subscription_id','payment_date','amount_cents','status'),
  activity_events=c('event_id','user_id','event_date','event_type'))

validate_sources <- function(data) {
  for (table in source_tables) {
    x<-data[[table]]
    if (!identical(names(x),source_columns[[table]])) stop('Unexpected columns in ',table,'.csv.')
    if (anyNA(x)) stop('Missing values in ',table,'.csv.')
    for (column in names(x)) {
      if (grepl('(_id|_cents|billing_days)$',column)) {
        v<-x[[column]]
        if (!is.numeric(v) || any(v!=floor(v) | v<=0 | v>2147483647)) {
          if (length(v)) stop('Invalid positive integer: ',table,'.',column)
        }
      }
      if (grepl('_date$',column)) {
        v<-x[[column]];parsed<-as.Date(v,format='%Y-%m-%d')
        if (anyNA(parsed) || any(format(parsed,'%Y-%m-%d')!=v)) stop('Invalid ISO date: ',table,'.',column)
      }
    }
  }
  if (!nrow(data$users) || nrow(data$users)>20000) stop('Expected 1 to 20,000 users.')
  if (any(data$users$signup_date<'2025-01-01' | data$users$signup_date>'2025-12-31')) stop('Signup outside the supported 2025 period.')
  if (!all(data$users$country %in% c('PL','DE','GB','UA'))) stop('Unsupported country.')
  invisible(TRUE)
}

read_sources <- function(source_dir,manifest_path) {
  m<-jsonlite::fromJSON(manifest_path,simplifyVector=FALSE)
  if (!identical(m$contract,'subscription-service-source') || !identical(m$contract_version,'2.0')) stop('Expected source contract version 2.0.')
  if (!identical(m$synthetic,TRUE) || !identical(m$currency,'EUR') ||
      !identical(m$observation_start,'2025-01-01') || !identical(m$observation_end,'2025-12-31')) stop('Unsupported dataset metadata.')
  if (length(m$seed)!=1 || !is.numeric(m$seed) || !is.finite(m$seed) || m$seed<0 || m$seed>2147483647 || m$seed!=floor(m$seed)) stop('Invalid dataset seed.')
  if (!setequal(names(m$files),source_tables) || anyDuplicated(names(m$files))) stop('The manifest must describe exactly five source tables.')
  data<-setNames(lapply(source_tables,function(table) {
    spec<-m$files[[table]];name<-paste0(table,'.csv')
    if (!identical(spec$file,name)) stop('Unexpected manifest filename.')
    file<-file.path(source_dir,name)
    if (!file.exists(file)) stop('Missing source file: ',name)
    if (!identical(digest::digest(file=file,algo='sha256',serialize=FALSE),spec$sha256)) stop('SHA-256 mismatch: ',name)
    x<-read.csv(file,stringsAsFactors=FALSE,check.names=FALSE)
    if (length(spec$rows)!=1 || !is.numeric(spec$rows) || nrow(x)!=spec$rows) stop('Row count mismatch: ',name)
    x
  }),source_tables)
  validate_sources(data)
  bounds<-c(m$min_users,m$max_users)
  if(length(bounds)!=2 || !is.numeric(bounds) || any(!is.finite(bounds)) || any(bounds!=floor(bounds)) || bounds[1]>bounds[2] || nrow(data$users)<bounds[1] || nrow(data$users)>bounds[2]) stop('User count is outside its declared range.')
  hash<-digest::digest(paste(vapply(m$files[source_tables],function(x)x$sha256,character(1)),collapse=''),algo='sha256',serialize=FALSE)
  expected<-paste0('seed-',format(m$seed,scientific=FALSE),'-',substr(hash,1,12))
  if (!identical(m$dataset_id,expected)) stop('Dataset identifier does not match its content.')
  if (length(m$user_count)!=1 || !is.numeric(m$user_count) || m$user_count!=nrow(data$users)) stop('User count does not match the manifest.')
  list(data=data,manifest=m)
}

read_bundle <- function(zip_path) {
  if (!file.exists(zip_path) || file.info(zip_path)$size>30*1024^2) stop('Select a ZIP smaller than 30 MB.')
  entries<-utils::unzip(zip_path,list=TRUE)
  if (anyDuplicated(entries$Name) || sum(entries$Length)>200*1024^2) stop('Duplicate ZIP entries or archive larger than the 200 MB unpacked limit.')
  folder<-tempfile('dataset-import-');dir.create(folder)
  complete<-FALSE;on.exit(if(!complete) unlink(folder,recursive=TRUE),add=TRUE)
  if (!'manifest.json' %in% entries$Name) stop('ZIP is missing manifest.json at its root.')
  # Only explicitly named contract files are extracted; arbitrary ZIP paths are ignored.
  utils::unzip(zip_path,files='manifest.json',exdir=folder)
  m<-jsonlite::fromJSON(file.path(folder,'manifest.json'),simplifyVector=FALSE)
  if (!identical(m$contract,'subscription-service-source')) stop('Unsupported dataset contract.')
  if (identical(m$contract_version,'1.0')) {
    # Read the original project's archives too, then normalize to the simple v2 format.
    legacy_tables<-c('settings','users','plans','subscriptions','payments','activity_events','experiment_assignments')
    expected<-paste0('data/raw/',legacy_tables,'.csv')
    if (!all(expected %in% entries$Name) || !setequal(names(m$files),legacy_tables)) stop('Incomplete legacy source bundle.')
    utils::unzip(zip_path,files=expected,exdir=folder)
    for (table in legacy_tables) {
      f<-file.path(folder,'data/raw',paste0(table,'.csv'));spec<-m$files[[table]]
      if (!identical(spec$file,paste0(table,'.csv')) || !identical(digest::digest(file=f,algo='sha256',serialize=FALSE),spec$sha256) || nrow(read.csv(f))!=spec$rows) stop('Invalid legacy table: ',table)
    }
    if (read.csv(file.path(folder,'data/raw/settings.csv'))$as_of!=m$observation_end) stop('Legacy observation period mismatch.')
    for (table in source_tables) file.copy(file.path(folder,'data/raw',paste0(table,'.csv')),folder)
    m$contract_version<-'2.0';m$generator<-'legacy-snapshot/1.0';m$files<-m$files[source_tables]
    m$user_count<-m$files$users$rows;m$min_users<-m$user_count;m$max_users<-m$user_count
    hash<-digest::digest(paste(vapply(m$files,function(x)x$sha256,character(1)),collapse=''),algo='sha256',serialize=FALSE)
    m$dataset_id<-paste0('seed-',format(m$seed,scientific=FALSE),'-',substr(hash,1,12))
    jsonlite::write_json(m,file.path(folder,'manifest.json'),pretty=TRUE,auto_unbox=TRUE)
    unlink(file.path(folder,'data'),recursive=TRUE)
  } else if (identical(m$contract_version,'2.0')) {
    expected<-paste0(source_tables,'.csv')
    if (!all(expected %in% entries$Name)) stop('ZIP must contain the five source CSVs at its root.')
    utils::unzip(zip_path,files=expected,exdir=folder)
  } else stop('Unsupported source contract version.')
  checked<-read_sources(folder,file.path(folder,'manifest.json'))
  complete<-TRUE
  list(path=folder,data=checked$data,manifest=checked$manifest)
}

if (sys.nframe()==0L) {
  args<-commandArgs(trailingOnly=FALSE);script<-sub('^--file=','',args[grepl('^--file=',args)])
  root<-if(length(script)) dirname(normalizePath(script[1])) else getwd()
  cli<-commandArgs(trailingOnly=TRUE)
  if (length(cli)!=2 || cli[2]!='--replace') stop('Usage: Rscript import_data.R path/to/dataset.zip --replace. This replaces the working data and results; data/baseline.zip is retained.')
  zip_path<-normalizePath(cli[1],mustWork=TRUE);setwd(root);source('analysis.R')
  imported<-read_bundle(zip_path);on.exit_cleanup<-imported$path
  snapshot<-analyse_dataset(imported,root)
  save_analysis(snapshot,root)
  unlink(c(imported$path,snapshot$path),recursive=TRUE)
  message('Working analysis replaced. Open results/report.html; refresh Power BI.')
}
