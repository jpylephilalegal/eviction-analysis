# Eviction Analysis Toolkit

This repository demonstrates how you can set up a system for analyzing
eviction data and make the data available to the public for analysis.
It provides instructions and code for creating a site such as
[https://eviction.philalegal.org](https://eviction.philalegal.org).

## Obtain court data

You will need to ask the court for data.  Look at the public docket
records and make a list of the information you see.

Many large court systems have an office that deal with bulk data
requests.  Ask this office for any order forms that they have.  The
court system may also have a policy about what data can be released.

Then prepare your data request.  Ask for everything you can get.  The
court system will likely not give you "everything"; you will probably
be expected to itemize the fields you want.  Try asking them for a
list of fields that exist in their database.  They might not have it,
or might not give it to you, but it does not hurt to ask.  Prepare an
itemized list of every field you see on the court's web site, or in
docket listings you have seen, or in any other documents you are able
to obtain.

The court may only be willing to give you data from a certain span of
years.  Ask for as much time as possible.  Also try to get
clarification about what filters they apply to produce data for a
particular span of time.  There are a number of dates associated with
a court case, so it is not necessarily obvious what a "2018" case is.
A case might be created on a certain date but then the start date may
be back-dated to an earlier date.  Cases may be assigned to years
based on filing date, or based on disposition date.  If you do any
trend analysis of the number of cases per year, you will want to be
sure you can trust data from the years at each end of the time period.
For example, if you conclude that a metric was low at the beginning of
the time period, but this conclusion is really just reflecting an
artifact of the way the data were filtered, your conclusion will be
misleading.

Even if you end up using only a subset of the data you obtain, it is
always better to have more data rather than less.  It is difficult to
anticipate in advance what data will be relevant for future analyses.

If data are not available from the court directly, you may need to
obtain the data through web scraping.

## Installation

Start up a virtual machine on the internet.  Microsoft Azure is a good
choice because Microsoft offers a generous annual credit to
non-profits.  Amazon Web Services is similar.

Any Linux platform will work, but these instructions will be for
Ubuntu or Debian systems.

Once you have a machine up and running, install the following software?

   apt-get install git libxml2-dev libxml2 udev libcurl4-openssl-dev \
   libgdal-dev libgdal20 libudunits2-dev libudunits2-data \
   libudunits2-0 gdebi-core libapache2-mod-proxy-html gdebi-core \
   libudunits2-dev libudunits2-data libudunits2-0 libudunits \
   postgresql redis
   wget https://download3.rstudio.org/ubuntu-14.04/x86_64/shiny-server-1.5.9.923-amd64.deb
   gdebi shiny-server-1.5.9.923-amd64.deb

This will install an Apache web server, the PostgreSQL database, the R
statistical package, and the Shiny web front end for R.

Then, there are a few configuration files that need to be created.

### `/etc/apache2/sites-available/eviction.philalegal.org.conf`

This is the web server configuration file.  It assumes that you have
installed SSL certificates for your domain in `/etc/ssl`.  At PLA, we
have a "wildcard" certificate for `*.philalegal.org`, so we can use the
`crt` and `pem` files and they support `eviction.philalegal.org`.  SSL
is complicated and beyond the scope of this README, but using SSL is
highly recommended.

The Apache configuration is non-trivial because Shiny uses websockets

    <VirtualHost *:80>
    ServerName eviction.philalegal.org
    ServerAdmin jpyle@philalegal.org

    DocumentRoot /var/www/html
    
    Redirect / https://eviction.philalegal.org/

    ErrorLog ${APACHE_LOG_DIR}/error.log

    # Possible values include: debug, info, notice, warn, error, crit,
    # alert, emerg.
    LogLevel warn

    CustomLog ${APACHE_LOG_DIR}/access.log combined
    </VirtualHost>
    <IfModule mod_ssl.c>
    <VirtualHost *:443>
	ServerName eviction.philalegal.org
	ServerAdmin jpyle@philalegal.org
	SSLEngine on
	SSLCertificateFile /etc/ssl/yourcert.crt
	SSLCertificateKeyFile /etc/ssl/yourcert.pem
	SSLProxyEngine on
	DocumentRoot /var/www/html
	<Proxy *>
	  Allow from localhost
	</Proxy>
	RewriteEngine on
	RewriteCond %{HTTP:Upgrade} =websocket
	RewriteRule /shiny/(.*) ws://localhost:3838/$1 [P,L]
	RewriteCond %{HTTP:Upgrade} !=websocket
	RewriteRule /shiny/(.*) http://localhost:3838/$1 [P,L]
	ProxyPass /shiny/ http://localhost:3838/
	ProxyPassReverse /shiny/ http://localhost:3838/
	ProxyPass /shiny-admin/ http://localhost:4151/
	ProxyPassReverse /shiny-admin/ http://localhost:4151/
	ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/
	<Directory "/usr/lib/cgi-bin">
	    AllowOverride None
	    Options -Indexes +ExecCGI -MultiViews +SymLinksIfOwnerMatch
	    Require all granted
	</Directory>
	<Directory /var/www/>
	    Options +Indexes +FollowSymLinks +MultiViews
	    AllowOverride None
	    Require all granted
	</Directory>
	Alias /html /usr/lib/cgi-bin/html/
	<Directory /usr/lib/cgi-bin/html/>
	    Options -Indexes +FollowSymLinks +MultiViews
	    AllowOverride None
	    Require all granted
	</Directory>

	ErrorLog ${APACHE_LOG_DIR}/error.log
	LogLevel warn

	CustomLog ${APACHE_LOG_DIR}/access.log combined
    </VirtualHost>
    </IfModule>

### `/var/www/html/index.html`

This file exists so that if a user accesses the root of your domain
(e.g., https://eviction.philalegal.org), the user will be redirected
to the Shiny app.

    <!doctype html>
    <html lang="en">
      <head>
	<meta charset="utf-8">
	<meta http-equiv="refresh" content="0; URL='https://eviction.philalegal.org/shiny/eviction/'" />
	<title>Eviction</title>
      </head>
      <body>
      </body>
    </html>

### `/etc/shiny-server/shiny-server.conf`

This is the configuration file for Shiny itself.

    # Instruct Shiny Server to run applications as the user "shiny"
    run_as shiny;

    # Define a server that listens on port 3838
    server {
      listen 3838;

      # Define a location at the base URL
      location / {

	# Host the directory of Shiny Apps stored in this directory
	site_dir /srv/shiny-server;

	# Log all Shiny output to files in this directory
	log_dir /var/log/shiny-server;

	# When a user visits the base URL rather than a particular application,
	# an index of the applications available in this directory will be shown.
	directory_index on;
      }
    }

### `/home/shiny/.Renviron`

In order to make sense of court data geographically, you will need to
use data from the United States Census Bureau.

The Census data table that is most helpful for analyzing
landlord-tenant data is B25003, "Occupied housing units."  This table
contains the number of owner-occupied housing unit and the number of
renter-occupied housing units.  In order to map data sensibly, you
can't just map the number of eviction cases in a zip code.  The fact
that a given zip code may have a large number of cases does not mean
that the zip code has a high rate of evictions; it may simply have a
lot of people.  Thus, in the statistics generated in the Shiny app,
eviction numbers have been normalized using the census data.

The Shiny app retrieves Census data and maps in real time from the
U.S. Census Bureau.  The work is done by the `tidycensus` package.

In order for `tidycensus` to be able to retrieve data from the Census
Bureau's servers, you need to [obtain an API key from the Census Bureau].

Once you have the API key, create the file `/home/shiny/.Renviron`
with contents in the following form:

    CENSUS_API_KEY='229383b33c2323546cecd8d79c7987b9667d9a78'

[obtain an API key from the Census Bureau]: https://api.census.gov/data/key_signup.html

## Schema of database

The specific format of the data you obtained from your court system
will be unique.  I have found that whatever form court data has, it is
helpful to refactor it into a few simplified tables: a table
representing attributes of a case, and a table representing events
that happen in a case.

We used a PostgreSQL database, but a MariaDB or MySQL database will
work just as well.

### The `ltcases` table

I collected the basic attributes about landlord-tenant cases into a
database table called `ltcases`.

These fields represent a subset of the fields we received from the
court.  They represent the fields that I considered to be important
for analysis.  In my case, I was merging data from two different court
databases, and these were the columns that each data set had in common.

								Table "public.ltdocksum"
		   Column        |           Type           | Collation | Nullable | Default 
	---------------------+--------------------------+-----------+----------+---------
	 docket_type         | text                     |           |          | 
	 case_category       | text                     |           |          | 
	 county_name         | text                     |           |          | 
	 court_office_code   | text                     |           |          | 
	 docket_number       | text                     |           |          | 
	 case_title          | text                     |           |          | 
	 filing_date         | timestamp with time zone |           |          | 
	 case_status         | text                     |           |          | 
	 claim_amount        | double precision         |           |          | 
	 monthly_rent_amount | double precision         |           |          | 
	 year                | integer                  |           |          | 
	 month               | integer                  |           |          | 
	 zip5                | bpchar                   |           |          | 
	 filing_month        | timestamp with time zone |           |          | 

### The `ltevents` table

For the events that happen in a case, I created a table with three
columns: a `docket_number` representing a unique docket, an
`eventdate` representing a date when a court event happened, and an
`eventtype` that signifies what the event was.

                     Table "public.ltevents"
     Column       | Type | Collation | Nullable | Default
    --------------+------+-----------+----------+---------
    docket_number | text |           |          |
    eventdate     | date |           |          |
    eventtype     | text |           |          |

The `eventtype` column contains a code for a type of docket event.
These are the events in the case that are meaningful.  Not all docket
entries will be worth including.  Also, an event in a case might go by
several different names, so you may need to consolidate.

The categories of docket entries that I considered to be significant
for Pennsylvania are:

* `AW`: Alias Writ of Possession obtained
* `AWS`: Alias Writ Served
* `CF`: Case Filed
* `CON`: Continuance granted
* `DJ`: Default judgment entered
* `JBA`: Judgment by agreement entered
* `JFD`: Judgment for defendant entered
* `PO`: Petition To Open filed
* `POD`: Petition To Open denied
* `POG`: Petition To Open granted
* `SATB`: Judgment Satisfied both as to money and possession
* `SATP`: Judgment Satisfied both as to possession
* `SATM`: Judgment Satisfied both as to money
* `WD`: Withdrawn
* `WP`: Writ of Possession obtained

## File contents

1. `cgi-bin`: contains code for generating the Sankey diagrams of
   eviction case processes based on the entries in the `ltevents`
   table.  These files go in `/usr/lib/cgi-bin`.
2. `shiny`: contains an R Shiny app for interactively exploring the
   eviction data.  The contents of this folder need to be copied into
   a directory called `/srv/shiny-server/eviction`.
    1. `shiny/server.R` - this contains the code that does the number crunching
    2. `shiny/ui.R` - this contains the code that specifies the layout
       of the Shiny user interface
	3. `shiny/data/captions.yml` - this is a data file loaded by
       `server.R` that contains explanatory captions for each screen
       in the system.
	4. `shiny/www` - this folder contains some static resources needed
	by the Shiny application.

## Adapting the code for a different jurisdiction

The Shiny application included here merges court data with Census data
and provides users with the ability to see data on maps and in plots.
Adapting it to a different jurisdiction involves significant
customization, but the example code is illustrative.

Most of the screens in the application are generated by R, but one
screen, called "Eviction process," is not based on R.  It consists of
an HTML file, `shiny/www/sankey.html`, which runs some JavaScript,
which retrieves JSON data from a web service running at
`cgi-bin/sankey.pl`.

To replicate the functionality of the application, you will need to
learn how R Shiny apps work and make substantial modifications to the
code so that it presents the type of data that is relevant to your
jurisdiction.

# Credits

This project was made possible by a grant from the Legal Services Corporation.
