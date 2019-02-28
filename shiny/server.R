library(shiny)
library(tidycensus)
library(tidyverse)
library(viridis)
library(leaflet)
library(stringr)
library(shinycssloaders)
library(sf)
library(acs)
library(noncensus)
library(RPostgreSQL)
library(yaml)

this_state <- "PA"
this_county <- "Philadelphia County"
this_county_short <- "Philadelphia"
this_state_long <- "Pennsylvania"
con <- dbConnect(dbDriver("PostgreSQL"), dbname = "eviction", host="localhost", user="jpyle", password="foobar")

captions <- read_yaml("data/captions.yml")
data(zip_codes)
options(tigris_use_cache = TRUE)

yearFormat <- function(x){
    sprintf("%.0f", x)
}
acs_sort <- function(df){
    df[order(df$GEOID),]
}

sankey <- function(input){
    if (input$area == this_state_long){
        the_url <- paste0("/html/sankeypa.html?start=", input$stateyearrange[1], '&end=', input$stateyearrange[2])
    }
    else{
        the_url <- paste0("/html/sankey.html?start=", input$yearrange[1], '&end=', input$yearrange[2])
    }
    print("Got past the_url")
    if (input$rentrange[1] != 0 || input$rentrange[2] != 2000){
        the_url <- paste(the_url, paste0('rentstart=', input$rentrange[1]), sep='&')
        the_url <- paste(the_url, paste0('rentend=', input$rentrange[2]), sep='&')
    }
    if (input$area == this_county_short){
        for (key in c("a", "b", "c", "publichousing", "defendant_represented", "plaintiff_represented")){
            if (input[[key]] != "Any"){
                the_url <- paste(the_url, paste(paste0(key, '=', input[[key]]), collapse='&'), sep='&')
            }
        }
        write(paste0("Zip is ", input$epzip), stderr())
        if (input$epzip != 'Any'){
            the_url <- paste(the_url, paste0('zip=', input$epzip), sep='&')
        }
        write(paste0("Census is ", input$epcensus), stderr())
        if (input$epcensus != 'Any'){
            the_url <- paste(the_url, paste0('census=', input$epcensus), sep='&')
        }
    }
    else{
        write(paste0("Zip is ", input$stateepzip), stderr())
        if (input$stateepzip != 'Any'){
            the_url <- paste(the_url, paste0('zip=', input$stateepzip), sep='&')
        }
        write(paste0("County is ", input$county), stderr())
        if (input$county != 'Any'){
            the_url <- paste(the_url, paste0('county=', input$county), sep='&')
        }
    }
    write(paste0("URL is ", the_url), stderr())
    the_url
}
shinyServer(function(input, output) {
    observe({
        input$a
        input$a_only
        input$b
        input$b_only
        input$c
        input$c_only
        input$publichousing
        input$defendant_represented
        input$plaintiff_represented
        input$stateepzip
        input$epzip
        input$county
        input$epcensus
        input$yearrange
        input$stateyearrange
        input$rentrange
        input$rent
        input$area
        process_url <<- sankey(input)
    })
    metricList = reactive({
        if (input$area == "Philadelphia"){
            return(c("Rented vs. owned", "Rented vs. owned change", "Ratio of licenses to units", "Ratio of licenses to units change", "Rental unit trends", "Lawsuit rate", "Lawsuit rate change", "Lawsuit trends", "Eviction process"))
        }
        else{
            return(c("Rented vs. owned", "Rented vs. owned change", "Rental unit trends", "Lawsuit rate", "Lawsuit rate change", "Lawsuit trends", "Eviction process"))
        }
    })
    output$metric <- renderUI({
        selectInput("metric", "Metric:", metricList())
    })
    output$frame <- renderUI({
        input$a
        input$a_only
        input$b
        input$b_only
        input$c
        input$c_only
        input$publichousing
        input$defendant_represented
        input$plaintiff_represented
        input$stateepzip
        input$epzip
        input$county
        input$epcensus
        input$yearrange
        input$stateyearrange
        input$rentrange
        input$area
        my_iframe <- tags$iframe(src=process_url)
        print(my_iframe)
        my_iframe
    })
    output$plot <- renderPlot({
        if (input$metric == "Lawsuit trends"){
            query_string <- "select year,"
            if (input$statistic == "Number of cases" || input$statistic == "Percentage of cases"){
                stat <- "count(id)"
            }
            else if (input$statistic == "Median ongoing rent"){
                stat <- "median(ongoing_rent::numeric)"
            }
            else if (input$statistic == "Median amount sought"){
                stat <- "median(amt_sought::numeric)"
            }
            else if (input$statistic == "Median rent sought"){
                stat <- "median(total_rent::numeric)"
            }
            else if (input$statistic == "Median months of rent sought"){
                stat <- "median(months::numeric)"
            }
            else if (input$statistic == "Average months of rent sought"){
                stat <- "avg(months::numeric)"
            }
            else if (input$statistic == "Median judgment amount"){
                stat <- "median(award_total_amount_due::numeric)"
            }
            query_string <- paste(query_string, stat, "as stat from ltdatahist where year >=", input$years[1], "and year <=", input$years[2])
            if (input$statistic == "Median ongoing rent"){
                query_string <- paste0(query_string, " and ongoing_rent::numeric > 0")
            }
            if (input$statistic == "Median amount sought"){
                query_string <- paste0(query_string, " and amt_sought::numeric > 0")
            }
            if (input$statistic == "Median rent sought"){
                query_string <- paste0(query_string, " and total_rent::numeric > 0")
            }
            if (input$statistic == "Median months of rent sought" || input$statistic == "Average months of rent sought"){
                query_string <- paste0(query_string, " and months::numeric > 0")
            }
            if (input$statistic == "Median judgment amount"){
                query_string <- paste0(query_string, " and award_total_amount_due::numeric > 0")
            }
            if (input$rent[1] != 0 || input$rent[2] != 2000){
                query_string <- paste(query_string, "and ongoing_rent >=", input$rent[1], "and ongoing_rent <=", input$rent[2])
            }
            if (input$census != "Any"){
                query_string <- paste0(query_string, " and census like '%", input$census, "%'")
            }
            if (input$zip != "Any"){
                query_string <- paste0(query_string, " and zip = '", input$zip, "'")
            }
            if (input$t_default_judgment == "True"){
                query_string <- paste(query_string, "and defendant_default_date is not null")
            }
            else if (input$t_default_judgment == "False"){
                query_string <- paste(query_string, "and defendant_default_date is null")
            }
            for (key in c("a", "b", "c", "possession_sought", "money_judgment_sought", "publichousing", "defendant_represented", "plaintiff_represented", "withdrawn", "petition_to_open", "jba", "jba_breach", "court_order", "judgment_for_defendant", "judgment_for_plaintiff", "satisfied", "writ_of_possession", "alias_writ", "alias_writ_served", "appeal")){
                t_key <- paste0('t_', key)
                if (input[[t_key]] == "True"){
                    query_string <- paste(query_string, "and", key)
                }
                else if (input[[t_key]] == "False"){
                    query_string <- paste(query_string, "and not", key)
                }
            }
            query_string <- paste(query_string, "group by year order by year")
            print(query_string)
            data.by.year <- dbGetQuery(con, query_string)
            if (input$statistic == "Percentage of cases"){
                total.by.year <- dbGetQuery(con, paste("select year, count(id) as total from ltdatahist where year >=", input$years[1], "and year <=", input$years[2], "group by year order by year"))
                data.by.year$prestat <- data.by.year$stat
                data.by.year$stat <- 100.0 * data.by.year$prestat / unlist(lapply(data.by.year$year, function(x){total.by.year$total[match(x, total.by.year$year)]}))
            }
            ggplot(data.by.year, aes(year, stat)) + geom_line(stat="identity", size=2, colour='blue') + xlab("Year") + ylab(input$statistic) + scale_x_continuous(labels=yearFormat, breaks=seq(input$years[1], input$years[2])) + expand_limits(y = 0) + theme(text=element_text(size=21))
        }
        else if (input$metric == 'Rental unit trends'){
            years <- seq(input$changeyears[1], input$changeyears[2])
            if (input$dtzip != 'Any' && years[1] == 2010){
                years <- years[-1]
            }
            numerator <- seq(from=0, to=0, along.with=years)
            denominator <- numerator
            licenses <- numerator
            odp_query <- "select a.year, sum(b.numberofunits) as units from year_list as a left outer join (select licensenum, max(zip) as zip, max(numberofunits) as numberofunits, max(census) as census, min(initialissuedate) as issuedate, min(inactivedate) as inactivedate from odplicenses where licensetype='Rental' group by licensenum) as b on (a.year >= date_part('year', b.issuedate) and (b.inactivedate is null or a.year <= date_part('year', b.inactivedate))"
            if (input$dtzip != 'Any'){
                odp_query <- paste0(odp_query, " and b.zip='", input$dtzip, "'")
            }
            else if (input$dtcensus != 'Any'){
                odp_query <- paste0(odp_query, " and b.census='", input$dtcensus, "'")
            }    
            odp_query <- paste0(odp_query, ") group by a.year")
            odp_info <- dbGetQuery(con, odp_query)
            for (indexno in seq_along(years)){
                licenses[indexno] <- odp_info$units[odp_info$year == years[indexno]]
            }
            if (input$dtzip != 'Any'){
                for (indexno in seq_along(years)){
                    tenure.renter <- acs_sort(get_acs(geography="zip code tabulation area", year=years[indexno], variables="B25003_003", geometry=FALSE))
                    tenure.total <- acs_sort(get_acs(geography="zip code tabulation area", year=years[indexno], variables="B25003_001", geometry=FALSE))
                    numerator[indexno] <- tenure.renter$estimate[tenure.renter$GEOID == input$dtzip]
                    denominator[indexno] <- tenure.total$estimate[tenure.renter$GEOID == input$dtzip]
                }
            }
            else{
                for (indexno in seq_along(years)){
                    tenure.renter <- acs_sort(get_acs(geography="tract", year=years[indexno], variables="B25003_003", state=this_state, county="Philadelphia County", geometry=FALSE))
                    tenure.total <- acs_sort(get_acs(geography="tract", year=years[indexno], variables="B25003_001", state=this_state, county="Philadelphia County", geometry=FALSE))
                    if (input$dtcensus != 'Any'){
                        numerator[indexno] <- tenure.renter$estimate[tenure.renter$GEOID == input$dtcensus]
                        denominator[indexno] <- tenure.total$estimate[tenure.renter$GEOID == input$dtcensus]                    
                    }
                    else{
                        numerator[indexno] <- sum(tenure.renter$estimate)
                        denominator[indexno] <- sum(tenure.total$estimate)
                    }
                }
            }
            data <- data.frame(year=years, numerator=numerator, denominator=denominator, licenses=licenses)
            if (input$dtstatistic == 'Number of renter-occupied units'){
                data$stat <- data$numerator
            }
            else if (input$dtstatistic == 'Rental percentage'){
                data$stat <- 100.0 * data$numerator / data$denominator
            }
            else if (input$dtstatistic == 'Ratio of licenses to units'){
                data$stat <- data$licenses / data$numerator
            }
            ggplot(data, aes(year, stat)) + geom_line(stat="identity", size=2, colour='blue') + xlab("Year") + ylab(input$dtstatistic) + scale_x_continuous(labels=yearFormat, breaks=seq(input$changeyears[1], input$changeyears[2])) + expand_limits(y = 0) + theme(text=element_text(size=21))
        }
        else{
            NULL
        }
    })
    output$mymap <- renderLeaflet({
        if(input$metric == "Eviction process" || input$metric == "Lawsuit trends" || input$metric == "Rental unit trends"){
            NULL
        }
        else{
            if(input$area == this_state_long){
                if (input$stateyear > 0){
                    acs.year = input$stateyear
                }
                else{
                    acs.year = 2016
                }
            }
            else{
                if (input$year > 0){
                    acs.year = input$year
                }
                else{
                    acs.year = 2017
                }
            }
            if (input$metric == "Rented vs. owned change" || input$metric == "Lawsuit rate change" || input$metric == "Ratio of licenses to units change"){
                if (input$area == this_state_long){
                    acs.year.lower = input$pachangeyears[1]
                    acs.year.upper = input$pachangeyears[2]
                    if (input$pachangeyears[1] == input$pachangeyears[2]){
                        if (input$pachangeyears[1] == 2010){
                            acs.year.upper = 2011
                        }
                        else {
                            acs.year.lower = acs.year.lower - 1 
                        }
                    }
                }
                else{
                    acs.year.lower = input$changeyears[1]
                    acs.year.upper = input$changeyears[2]
                    if (input$changeyears[1] == input$changeyears[2]){
                        if (input$changeyears[1] == 2010){
                            acs.year.upper = 2011
                        }
                        else {
                            acs.year.lower = acs.year.lower - 1 
                        }
                    }
                }
            }
            if(input$area == this_state_long){
                if (input$metric == "Rented vs. owned change" || input$metric == "Lawsuit rate change"){
                    if (acs.year.upper == 2010){
                        acs.year.upper = 2011
                    }
                    if (acs.year.lower == 2010){
                        acs.year.lower = 2011
                    }
                    tenure.renter.upper.all <- acs_sort(get_acs(geography="zip code tabulation area", year=acs.year.upper, variables="B25003_003", geometry=TRUE))
                    tenure.total.upper.all <- acs_sort(get_acs(geography="zip code tabulation area", year=acs.year.upper, variables="B25003_001", geometry=TRUE))
                    tenure.renter.lower.all <- acs_sort(get_acs(geography="zip code tabulation area", year=acs.year.lower, variables="B25003_003", geometry=TRUE))
                    tenure.total.lower.all <- acs_sort(get_acs(geography="zip code tabulation area", year=acs.year.lower, variables="B25003_001", geometry=TRUE))
                    tenure.renter.upper = tenure.renter.upper.all[tenure.renter.upper.all$GEOID %in% zip_codes$zip[zip_codes$state == 'PA'], ]
                    tenure.total.upper = tenure.total.upper.all[tenure.total.upper.all$GEOID %in% zip_codes$zip[zip_codes$state == 'PA'], ]
                    tenure.renter.lower = tenure.renter.lower.all[tenure.renter.lower.all$GEOID %in% zip_codes$zip[zip_codes$state == 'PA'], ]
                    tenure.total.lower = tenure.total.lower.all[tenure.total.lower.all$GEOID %in% zip_codes$zip[zip_codes$state == 'PA'], ]
                }
                else{
                    if (acs.year == 2010){
                        acs.year = 2011
                    }
                    tenure.renter.all <- acs_sort(get_acs(geography="zip code tabulation area", year=acs.year, variables="B25003_003", geometry=TRUE))
                    tenure.total.all <- acs_sort(get_acs(geography="zip code tabulation area", year=acs.year, variables="B25003_001", geometry=TRUE))
                    tenure.renter = tenure.renter.all[tenure.renter.all$GEOID %in% zip_codes$zip[zip_codes$state == 'PA'], ]
                    tenure.total = tenure.total.all[tenure.total.all$GEOID %in% zip_codes$zip[zip_codes$state == 'PA'], ]
                }
                if (input$metric == "Lawsuit rate"){
                    lawsuits.zip <- dbGetQuery(con, paste0("select zip5, count(docket_number) from ltdocksum where year=", input$year, " group by zip5"))
                    tenure.renter$lawsuits <- unlist(lapply(tenure.renter$GEOID, function(x){lawsuits.zip$count[match(x, lawsuits.zip$zip5)]}))
                    tenure.renter$prop <- tenure.renter$lawsuits/tenure.renter$estimate
                    tenure.renter$prop[tenure.renter$estimate < 100] <- NA
                    tenure.renter$desc <- sprintf("Lawsuits: %.0f", tenure.renter$lawsuits)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Renter-occupied units: %.0f", tenure.renter$estimate), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Ratio of lawsuits in %.0f to renter-occupants: %.2f", input$year, tenure.renter$prop), sep='<br>')
                    the_title <- "Lawsuit rate"
                    the_labels <- c("Lower", "", "", "", "", "", "", "", "", "Higher")
                }
                else if (input$metric == "Rented vs. owned"){
                    tenure.renter$prop <- tenure.renter$estimate/tenure.total$estimate
                    tenure.renter$prop[tenure.total$estimate < 100] <- NA
                    tenure.renter$desc <- sprintf("Renter-occupied units: %.0f", tenure.renter$estimate)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("All occupied units: %.0f", tenure.total$estimate), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Renter-occupied percentage: %.2f%%", 100.0*tenure.renter$prop), sep='<br>')
                    the_title <- "Renters"
                    the_labels <- c("Fewer", "", "", "", "", "", "", "", "", "More")
                }
                else if (input$metric == "Lawsuit rate change"){
                    lawsuits.zip.upper <- dbGetQuery(con, paste0("select zip5, count(docket_number) from ltdocksum where year=", acs.year.upper, " group by zip5"))
                    lawsuits.zip.lower <- dbGetQuery(con, paste0("select zip5, count(docket_number) from ltdocksum where year=", acs.year.lower, " group by zip5"))
                    tenure.renter.upper$lawsuits <- unlist(lapply(tenure.renter.upper$GEOID, function(x){lawsuits.zip.upper$count[match(x, lawsuits.zip.upper$zip5)]}))
                    tenure.renter.lower$lawsuits <- unlist(lapply(tenure.renter.lower$GEOID, function(x){lawsuits.zip.lower$count[match(x, lawsuits.zip.lower$zip5)]}))
                    tenure.renter.upper$prop <- tenure.renter.upper$lawsuits/tenure.renter.upper$estimate
                    tenure.renter.lower$prop <- tenure.renter.lower$lawsuits/tenure.renter.lower$estimate
                    tenure.renter.upper$prop[tenure.renter.upper$estimate < 100] <- NA
                    tenure.renter.lower$prop[tenure.renter.lower$estimate < 100] <- NA
                    tenure.renter <- tenure.renter.lower
                    tenure.renter$prop <- (tenure.renter.upper$prop - tenure.renter.lower$prop)/tenure.renter.lower$prop
                    tenure.renter$desc <- sprintf("Lawsuit rate in %.0f: %.2f", acs.year.lower, tenure.renter.lower$prop)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Lawsuit rate in %.0f: %.2f", acs.year.upper, tenure.renter.upper$prop), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Lawsuit rate changed by: %.2f%%", 100.0*tenure.renter$prop), sep='<br>')
                    the_title <- "Lawsuit rate change"
                    the_labels <- c("Negative", "", "", "", "", "", "", "", "", "Positive")
                }
                else if (input$metric == "Rented vs. owned change"){
                    tenure.renter.upper$prop <- tenure.renter.upper$estimate/tenure.total.upper$estimate
                    tenure.renter.lower$prop <- tenure.renter.lower$estimate/tenure.total.lower$estimate
                    tenure.renter.upper$prop[tenure.total.upper$estimate < 100] <- NA
                    tenure.renter.lower$prop[tenure.total.lower$estimate < 100] <- NA
                    tenure.renter.lower$prop[tenure.total.upper$estimate < 100] <- NA
                    tenure.renter.upper$prop[tenure.total.lower$estimate < 100] <- NA
                    tenure.renter <- tenure.renter.lower
                    tenure.renter$prop <- (tenure.renter.upper$prop - tenure.renter.lower$prop)/tenure.renter.lower$prop
                    tenure.renter$desc <- sprintf("Rental percentage in %.0f: %.2f%%", acs.year.lower, 100.0*tenure.renter.lower$prop)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Rental percentage in %.0f: %.2f%%", acs.year.upper, 100.0*tenure.renter.upper$prop), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Rental percentage changed by: %.2f%%", 100.0*tenure.renter$prop), sep='<br>')
                    the_title <- "Rental percentage change"
                    the_labels <- c("Negative", "", "", "", "", "", "", "", "", "Positive")
                }
            }
            else{
                if (input$metric == "Rented vs. owned change" || input$metric == "Lawsuit rate change" || input$metric == "Ratio of licenses to units change"){
                    tenure.renter.upper <- acs_sort(get_acs(geography="tract", year=acs.year.upper, variables="B25003_003", state=this_state, county="Philadelphia County", geometry=TRUE))
                    tenure.total.upper <- acs_sort(get_acs(geography="tract", year=acs.year.upper, variables="B25003_001", state=this_state, county="Philadelphia County", geometry=TRUE))
                    tenure.renter.lower <- acs_sort(get_acs(geography="tract", year=acs.year.lower, variables="B25003_003", state=this_state, county="Philadelphia County", geometry=TRUE))
                    tenure.total.lower <- acs_sort(get_acs(geography="tract", year=acs.year.lower, variables="B25003_001", state=this_state, county="Philadelphia County", geometry=TRUE))
                }
                else{
                    tenure.renter <- acs_sort(get_acs(geography="tract", year=acs.year, variables="B25003_003", state=this_state, county="Philadelphia County", geometry=TRUE))
                    tenure.total <- acs_sort(get_acs(geography="tract", year=acs.year, variables="B25003_001", state=this_state, county="Philadelphia County", geometry=TRUE))
                }
                if (input$metric == "Lawsuit rate"){
                    lawsuits.census <- dbGetQuery(con, paste0("select census, count(id) from ltdatahist where year=", input$year, " group by census"))
                    lawsuits.census$GEOID <- substr(lawsuits.census$census, 8, 18)
                    tenure.renter$lawsuits <- unlist(lapply(tenure.renter$GEOID, function(x){lawsuits.census$count[match(x, lawsuits.census$GEOID)]}))
                    tenure.renter$prop <- tenure.renter$lawsuits/tenure.renter$estimate
                    tenure.renter$prop[tenure.renter$estimate < 100] <- NA
                    tenure.renter$desc <- sprintf("Lawsuits: %.0f", tenure.renter$lawsuits)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Renter-occupied units: %.0f", tenure.renter$estimate), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Ratio of lawsuits in %.0f to renter-occupants: %.2f", input$year, tenure.renter$prop), sep='<br>')
                    the_title <- "Lawsuit rate"
                    the_labels <- c("Lower", "", "", "", "", "", "", "", "", "Higher")
                }
                else if (input$metric == "Rented vs. owned"){
                    tenure.renter$prop <- tenure.renter$estimate/tenure.total$estimate
                    tenure.renter$prop[tenure.total$estimate < 100] <- NA
                    tenure.renter$desc <- sprintf("Renter-occupied units: %.0f", tenure.renter$estimate)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("All occupied units: %.0f", tenure.total$estimate), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Renter-occupied percentage: %.2f%%", 100.0*tenure.renter$prop), sep='<br>')
                    the_title <- "Renters"
                    the_labels <- c("Fewer", "", "", "", "", "", "", "", "", "More")
                }
                else if (input$metric == "Lawsuit rate change"){
                    lawsuits.census.upper <- dbGetQuery(con, paste0("select census, count(id) from ltdatahist where year=", acs.year.upper, " group by census"))
                    lawsuits.census.lower <- dbGetQuery(con, paste0("select census, count(id) from ltdatahist where year=", acs.year.lower, " group by census"))
                    lawsuits.census.upper$GEOID <- substr(lawsuits.census.upper$census, 8, 18)
                    lawsuits.census.lower$GEOID <- substr(lawsuits.census.lower$census, 8, 18)
                    tenure.renter.upper$lawsuits <- unlist(lapply(tenure.renter.upper$GEOID, function(x){lawsuits.census.upper$count[match(x, lawsuits.census.upper$GEOID)]}))
                    tenure.renter.lower$lawsuits <- unlist(lapply(tenure.renter.lower$GEOID, function(x){lawsuits.census.lower$count[match(x, lawsuits.census.lower$GEOID)]}))
                    tenure.renter.upper$prop <- tenure.renter.upper$lawsuits/tenure.renter.upper$estimate
                    tenure.renter.lower$prop <- tenure.renter.lower$lawsuits/tenure.renter.lower$estimate
                    tenure.renter.upper$prop[tenure.renter.upper$estimate < 100] <- NA
                    tenure.renter.lower$prop[tenure.renter.lower$estimate < 100] <- NA
                    tenure.renter <- tenure.renter.lower
                    tenure.renter$prop <- (tenure.renter.upper$prop - tenure.renter.lower$prop)/tenure.renter.lower$prop
                    tenure.renter$desc <- sprintf("Lawsuit rate in %.0f: %.2f", acs.year.lower, tenure.renter.lower$prop)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Lawsuit rate in %.0f: %.2f", acs.year.upper, tenure.renter.upper$prop), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Lawsuit rate changed by: %.2f%%", 100.0*tenure.renter$prop), sep='<br>')
                    the_title <- "Lawsuit rate change"
                    the_labels <- c("Negative", "", "", "", "", "", "", "", "", "Positive")
                }
                else if (input$metric == "Rented vs. owned change"){
                    tenure.renter.upper$prop <- tenure.renter.upper$estimate/tenure.total.upper$estimate
                    tenure.renter.lower$prop <- tenure.renter.lower$estimate/tenure.total.lower$estimate
                    tenure.renter.upper$prop[tenure.total.upper$estimate < 100] <- NA
                    tenure.renter.lower$prop[tenure.total.lower$estimate < 100] <- NA
                    tenure.renter.lower$prop[tenure.total.upper$estimate < 100] <- NA
                    tenure.renter.upper$prop[tenure.total.lower$estimate < 100] <- NA
                    tenure.renter <- tenure.renter.lower
                    tenure.renter$prop <- (tenure.renter.upper$prop - tenure.renter.lower$prop)/tenure.renter.lower$prop
                    tenure.renter$desc <- sprintf("Rental percentage in %.0f: %.2f%%", acs.year.lower, 100.0*tenure.renter.lower$prop)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Rental percentage in %.0f: %.2f%%", acs.year.upper, 100.0*tenure.renter.upper$prop), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Rental percentage changed by: %.2f%%", 100.0*tenure.renter$prop), sep='<br>')
                    the_title <- "Rental percentage change"
                    the_labels <- c("Negative", "", "", "", "", "", "", "", "", "Positive")
                }
                else if (input$metric == "Ratio of licenses to units"){
                    licensed.units <- dbGetQuery(con, paste0("select census, units from units_by_census where year=", input$year, " order by census"))
                    licensed.units$GEOID <- licensed.units$census
                    tenure.renter$units <- unlist(lapply(tenure.renter$GEOID, function(x){licensed.units$units[match(x, licensed.units$GEOID)]}))
                    tenure.renter$prop <- tenure.renter$units / tenure.renter$estimate
                    tenure.renter$prop[tenure.renter$estimate < 100] <- NA
                    tenure.renter$desc <- sprintf("Licensed units: %.0f", tenure.renter$units)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Renter-occupied units: %.0f", tenure.renter$estimate), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Ratio of licensed units to renter-occupied units: %.2f", tenure.renter$prop), sep='<br>')
                    the_title <- "Licenses/rental unit ratio"
                    the_labels <- c("Lower", "", "", "", "", "", "", "", "", "Higher")
                }
                else if (input$metric == "Ratio of licenses to units change"){
                    licensed.units.upper <- dbGetQuery(con, paste0("select census, units from units_by_census where year=", input$changeyears[1], " order by census"))
                    licensed.units.upper$GEOID <- licensed.units.upper$census
                    licensed.units.lower <- dbGetQuery(con, paste0("select census, units from units_by_census where year=", input$changeyears[2], " order by census"))
                    licensed.units.lower$GEOID <- licensed.units.lower$census
                    tenure.renter.lower$units <- unlist(lapply(tenure.renter.lower$GEOID, function(x){licensed.units.lower$units[match(x, licensed.units.lower$GEOID)]}))
                    tenure.renter.lower$prop <- tenure.renter.lower$units / tenure.renter.lower$estimate
                    tenure.renter.lower$prop[tenure.renter.lower$estimate < 100] <- NA
                    tenure.renter.upper$units <- unlist(lapply(tenure.renter.upper$GEOID, function(x){licensed.units.upper$units[match(x, licensed.units.upper$GEOID)]}))
                    tenure.renter.upper$prop <- tenure.renter.upper$units / tenure.renter.upper$estimate
                    tenure.renter.upper$prop[tenure.renter.upper$estimate < 100] <- NA
                    tenure.renter <- tenure.renter.lower
                    tenure.renter$prop <- (tenure.renter.upper$prop - tenure.renter.lower$prop)/tenure.renter.lower$prop
                    tenure.renter$desc <- sprintf("Ratio of licensed units to renter-occupied units in %.0f: %.2f", input$changeyears[1], tenure.renter.lower$prop)
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Ratio of licensed units to renter-occupied units in %.0f: %.2f", input$changeyears[2], tenure.renter.upper$prop), sep='<br>')
                    tenure.renter$desc <- paste(tenure.renter$desc, sprintf("Ratio of licensed units to renter-occupied units changed by: %.0f%%", 100.0*tenure.renter$prop), sep='<br>')
                    the_title <- "Licenses/rental ratio change"
                    the_labels <- c("Negative", "", "", "", "", "", "", "", "", "Positive")
                }
            }
            pal <- colorQuantile(palette = "viridis", domain = tenure.renter$prop, n = 10)
            tenure.renter %>%
            st_transform(crs = "+init=epsg:4326") %>%
            st_zm() %>%
            leaflet() %>%
            addProviderTiles(provider = "CartoDB.Positron") %>%    
            addPolygons(popup = ~ paste(paste0('<strong>', str_extract(NAME, "^([^,]*)"), '</strong>'), desc, sep='<br>'),
                        stroke = FALSE,
                        smoothFactor = 0,
                        fillOpacity = 0.7,
                        color = ~ pal(prop)) %>%
            addLegend("bottomright", 
                      colors = sapply(quantile(tenure.renter$prop, seq(from=0, to=1, length.out=10), na.rm=TRUE), pal), 
                      values = ~ prop,
                      title = the_title,
                      labels = the_labels,
                      opacity = 1)
        }
    })
    output$caption <- renderText({
        if (input$metric == "Lawsuit trends"){
            captions[[input$metric]][["Show"]][[input$statistic]]
        }
        else if (input$metric == "Rental unit trends"){
            captions[[input$metric]][[input$dtstatistic]]
        }
        else{
            captions[[input$metric]]
        }
    })
})
