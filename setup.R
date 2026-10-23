# Inspect installation without preloading package namespaces.
options(repos=c(CRAN='https://cloud.r-project.org'),timeout=600)
packages<-c('shiny','DBI','RSQLite','ggplot2','jsonlite','digest','zip','base64enc')
missing<-setdiff(packages,rownames(installed.packages()))
if(length(missing))install.packages(missing)
# Check loading in a fresh R process, so dependency updates cannot conflict with old namespaces.
check<-paste0('for(p in c(',paste(sprintf('"%s"',packages),collapse=','),')) { message("Checking ",p);loadNamespace(p) }')
status<-system2(file.path(R.home('bin'),'Rscript'),c('--vanilla','-e',shQuote(check)))
if(status!=0)stop('Dependency loading failed. See the specific package error above.')
message('Dependencies are ready. Run Rscript start.R.')
