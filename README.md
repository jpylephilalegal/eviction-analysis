# Eviction Analysis Toolkit

This repository demonstrates how you can set up a system for analyzing eviction data and make the data available to the public for analysis.  This respository demonstrates how to create a site such as [https://eviction.philalegal.org](https://eviction.philalegal.org).

## Prerequisites

1. Obtain court data (varies by jurisdiction)
2. Import data into database following the Schema (see below).
3. Install Apache, Perl, R and Shiny.

## Installation

   apt-get install git libxml2-dev libxml2 udev libcurl4-openssl-dev libgdal-dev libgdal20 libudunits2-dev libudunits2-data libudunits2-0 gdebi-core libapache2-mod-proxy-html gdebi-core libudunits2-dev libudunits2-data libudunits2-0 libudunits
   wget https://download3.rstudio.org/ubuntu-14.04/x86_64/shiny-server-1.5.7.907-amd64.deb
   gdebi shiny-server-1.5.7.907-amd64.deb

### `/etc/apache2/sites-available/eviction.philalegal.org.conf`

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
    SSLCertificateFile /etc/ssl/alphassl/wildcard.crt
    SSLCertificateKeyFile /etc/ssl/alphassl/wildcard.pem
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

## Schema

The raw court data needs to be refactored into a table with three columns: an `id` representing a unique docket, an `eventdate` representing a date when a court event happened, and an `eventtype` that signifies what the event was.

### The `ltevents` table

                 Table "public.ltevents"
     Column   | Type | Collation | Nullable | Default
    ----------+------+-----------+----------+---------
    id        | text |           |          |
    eventdate | date |           |          |
    eventtype | text |           |          |

The `eventtype` options are:

* AW: Alias Writ of Possession obtained
* AWS: Alias Writ Served
* CF: Case Filed
* CON: Continuance granted
* DJ: Default judgment entered (not available outside of Philadelphia)
* JBA: Judgment by agreement entered
* JFD: Judgment for defendant entered
* PO: Petition To Open filed
* POD: Petition To Open denied
* POG: Petition To Open granted
* SATB: Judgment Satisfied both as to money and possession
* SATP: Judgment Satisfied both as to possession
* SATM: Judgment Satisfied both as to money
* WD: Withdrawn
* WP: Writ of Possession obtained

## File contents

1. `cgi-bin`: contains code for generating the Sankey diagrams of eviction case processes based on the entries in the `ltevents` table.
2. `shiny`: contains an R Shiny app for interactively exploring the eviction data.

# Credits

This project was made possible by a grant from the Legal Services Corporation.