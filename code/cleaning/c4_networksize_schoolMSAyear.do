/******************************
c4_networksize_schoolMSAyear.do

Richard Jin
last modified: 2/18/25
******************************/

*Purpose: Calculate college alumni network size for each school x MSA x year
*Merge positions file with user education file
*Include all degrees since we have many missing degree types, which makes it hard to separate Bachelors networks from all networks
*Caveat/limitation: lots of workers in positions file don't have a record in educ file

*Process one year at a time for computational efficiency
*run as array job passing 1st argument `1' as the year

*Still need to figure out what to do for simultaneous positions in two MSAs
*For now, count both positions

cap log close
*change directory
cd "/yourpath"
log using "./logs/cleaning/c4_networksize_schoolMSAyear`1'.log", replace

*input- cleaned individual education file
local educJan60Dec19_clean "./data_cleaned/individualeduc_Jan60Dec19_cleaned.dta"

*input- individual positions file, Jan 2010 to Dec 2019
local posJan10Dec19_csv "./data_raw/positions/individualpositions_us_Jan2010Dec2019.csv"
*input- individual positions file, jobs with start date before 2010 but present in 2010-2019
local pospreJan10_csv "./data_raw/positions/individualpositions_us_preJan2010.csv"

*input- US school mappings
local USschooldta "./data_constructed/SchoolCBSAMatching/schools_mapped_to_metro.dta"

*output- school x Metro x year network size
*all degrees
local schoolXmetroX`1'_all "./data_constructed/c4_schoolmetro`1'_alldegreesnetworksize.dta"
*bach only
local schoolXmetroX`1'_bach "./data_constructed/c4_schoolmetro`1'_bachdegreesnetworksize.dta"

*output- school x field x Metro x year network size
*all degrees
local schoolXfieldXmetroX`1'_all "./data_constructed/c4_schoolfieldmetro`1'_alldegreesnetworksize.dta"
*bach only
local schoolXfieldXmetroX`1'_bach "./data_constructed/c4_schoolfieldmetro`1'_bachdegreesnetworksize.dta"

/*******************
1. Setup
*******************/

*get US positions and drop unnecessary variables for calculation
import delimited using `posJan10Dec19_csv', clear
keep user_id metro_area startdate enddate weight
tempfile postJan10Dec19_sub
save `postJan10Dec19_sub', replace

import delimited using `pospreJan10_csv', clear
keep user_id metro_area startdate enddate weight
append using `postJan10Dec19_sub'

gen year_start = substr(startdate,1,4)
destring year_start, replace
gen year_end = substr(enddate,1,4)
destring year_end, replace
replace year_end = 2019 if year_end == . // jobs where user is still present
drop startdate enddate

*keep jobs in the given year
keep if year_start <= `1' & year_end >= `1'

*NECESSARY CLEAN- aggregate metro areas
replace metro_area = "los angeles metropolitan area" if metro_area == "anaheim metropolitan area"
replace metro_area = "los angeles metropolitan area" if metro_area == "long beach metropolitan area"
replace metro_area = "los angeles metropolitan area" if metro_area == "riverside metropolitan area"
replace metro_area = "miami metropolitan area" if metro_area == "fort lauderdale metropolitan area"
replace metro_area = "miami metropolitan area" if metro_area == "west palm beach metropolitan area"
replace metro_area = "dallas metropolitan area" if metro_area == "fort worth metropolitan area"
replace metro_area = "seattle metropolitan area" if metro_area == "tacoma metropolitan area"

*get a list of users in positions file
preserve
keep user_id
bys user_id: keep if _n == 1
tempfile userlist
save `userlist', replace
restore

/**************************
2. Merge on educ histories
**************************/

*trim the US schools dataset and keep metro var only
preserve
use `USschooldta', clear
keep university_name unitid instnm instcat linkedin_metro_area
rename linkedin_metro_area school_metro_area
drop if unitid == .
tempfile USschools
save `USschools', replace
restore

*work with cleaned educ file
*Trim educ file by keeping only users who show up in positions file
preserve
use `educJan60Dec19_clean', clear
keep user_id university_name startdate enddate degree field
merge m:1 user_id using `userlist'
keep if _m == 3
drop _m

*merge on school info for US schools only
gen university_name2 = university_name // convert strL to str# for merge
drop university_name
rename university_name2 university_name
merge m:1 university_name using `USschools'
keep if _m == 3
drop _m

*get end years of educ spells- the months are almost all January anyway, so only year is required and not yearmonth
gen year_end_deg = substr(enddate,1,4)
destring year_end_deg, replace

tempfile merged_educ
save `merged_educ', replace
restore

*for each position, merge on all the user's education records
joinby user_id using `merged_educ'

*only keep people if they are in job in same year (or later) as graduation, aka only keep true alums
*so, if someone is in job in 2015 and graduated with BA from Berkeley in 2015 or earlier, they stay, but if that same person graduated with MA from Stanford in 2018, the spell x Stanford record goes away
keep if year_end_deg <= `1'

/**************************
3. Collapse
**************************/

*want dataset at school x metro x year level with counts (unweighted and weighted)
*weights are by position
gen c=1
preserve
collapse (sum) N_uw=c N_w=weight, by(unitid instnm school_metro_area metro_area)
gen logsize_uw = log(N_uw)
gen logsize_w = log(N_w)

save `schoolXmetroX`1'_all', replace
restore

*now do Bachelors degrees only
preserve
keep if degree == "3_Bachelor"
collapse (sum) N_uw=c N_w=weight, by(unitid instnm school_metro_area metro_area)
gen logsize_uw = log(N_uw)
gen logsize_w = log(N_w)

save `schoolXmetroX`1'_bach', replace
restore

*now want dataset at school x field x metro x year level with counts (unweighted and weighted)
*weights are by position
preserve
collapse (sum) N_uw=c N_w=weight, by(unitid instnm school_metro_area field metro_area)
gen logsize_uw = log(N_uw)
gen logsize_w = log(N_w)

save `schoolXfieldXmetroX`1'_all', replace
restore

*now do Bachelors degrees only
preserve
keep if degree == "3_Bachelor"
collapse (sum) N_uw=c N_w=weight, by(unitid instnm school_metro_area field metro_area)
gen logsize_uw = log(N_uw)
gen logsize_w = log(N_w)

save `schoolXfieldXmetroX`1'_bach', replace
restore

cap log close
