# Eviction Analysis Toolkit

This repository demonstrates how you can set up a system for analyzing eviction data and make the data available to the public for analysis

## Prerequisites

1. Obtain court data (varies by jurisdiction)
2. Import data into database following the schema
3. Install Perl
4. Install R and Shiny

## Schema

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