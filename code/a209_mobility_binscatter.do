/*******************************************
a209_mobility_binscatter.do

Richard Jin
last modified: 9/11/25
*******************************************/

/*Purpose:
Binscatter for descriptive analysis
Two outcomes: 1) outmobility (at individual level), 2) directed mobility (collapse to school x location level)

RHS: average log network size 2010-2019
*/

clear all
set maxvar 32767

ssc install binscatter

local file count

cap log close
*change directory
cd "/yourpath"
log using "./logs/analysis/a209_mobility_binscatter.log", replace

*input- school network size terciles, use to get average yearly network size
local c8_out_all "./data_constructed/c8_networksizeterciles_all.dta"

*input- worker x location data for directed mobility
local c17_workerlayoffmetro_`file' "./data_constructed/c17_workerlayoffmetro_1yrpost.dta"

*input- worker x spell sample for outmobility
local c14_estimationsample_`file' "./data_constructed/c14_estimationsample_layoffsclosures_`file'.dta"

*output- two binscatters
*own deg highest, networks based on number total degrees
local out_scatter "./output/figures/a209_outmobility_binscatter.png"
local dir_scatter "./output/figures/a209_locationchoice_binscatter.png"

/**********************************************************
1. Outmobility binscatter
**********************************************************/

*get event dates for layoff and closure events
use `c14_estimationsample_`file'', clear
gen layoffclosure_dummy = (layoffclosure_id != "")
bys user_id: egen has_layoffclosure = max(layoffclosure_dummy) // all c5 workers should have this value equal 1, but may be missing bc of dropping overlapping spells
keep if has_layoffclosure == 1
gen layoffclosure_user_tag = 0
bys layoffclosure_id user_id: replace layoffclosure_user_tag = 1 if _n == 1
replace layoffclosure_user_tag = 0 if layoffclosure_id == ""
bys layoffclosure_id: egen layoffclosure_numworkers = total(layoffclosure_user_tag) // number of matched users in a layoff
tempfile c14_updated
save `c14_updated', replace

*switch to quarterly time
expand 12 // right now data is at yearly level, so we expand to monthly first and then collapse back to quarterly (easier than going quarterly)
bys user_id position_id year: gen month = _n
gen quarter = .
replace quarter = 1 if inlist(month,1,2,3)
replace quarter = 2 if inlist(month,4,5,6)
replace quarter = 3 if inlist(month,7,8,9)
replace quarter = 4 if inlist(month,10,11,12)
foreach type in start end {
  gen quarter_`type' = .
  replace quarter_`type' = 1 if inlist(month_`type',1,2,3)
  replace quarter_`type' = 2 if inlist(month_`type',4,5,6)
  replace quarter_`type' = 3 if inlist(month_`type',7,8,9)
  replace quarter_`type' = 4 if inlist(month_`type',10,11,12)
}

gen keepobs = 0
replace keepobs = 1 if year_start < year & year_end > year
replace keepobs = 1 if year_start < year & year_end == year & month_end >= month
replace keepobs = 1 if year_start == year & year_end == year & month_start <= month & month_end >= month
replace keepobs = 1 if year_start == year & year_end > year & month_start <= month

keep if keepobs == 1
bys user_id metro_area year quarter: gen monthsinquarter = _N
bys user_id year quarter: egen max_monthsinquarter = max(monthsinquarter)
bys user_id year quarter: egen user_numlayoffs_qtr = total(layoffclosure_dummy) // some quarters only have one layoff and we want to keep it regardless of if it's modal metro
keep if monthsinquarter == max_monthsinquarter | user_numlayoffs_qtr == 1 // keep modal metro in quarter or single layoff event
bys user_id year quarter: egen max_lc_numworkers = max(layoffclosure_numworkers) // if user has multiple layoff events in same quarter and modal metro, keep the biggest one
keep if layoffclosure_numworkers == max_lc_numworkers
bys user_id year quarter: keep if _n == 1 // collapse to worker x year level
sort user_id layoffclosure_id year quarter // layoff id filled for all year-quarter, only keep dummy for end year-quarter
by user_id layoffclosure_id: replace layoffclosure_dummy = 0 if _n != _N
replace layoffclosure_dummy = 0 if year != year_end | quarter != quarter_end // previous line isn't perfect, as some layoffs happen in 2016 Q2, so 2016 year Q2 gets dropped, but the last obs is still recording the layoffid even tho another layoffid happened in a later 2016 Q
replace layoffclosure_id = "" if layoffclosure_dummy == 0

*define event time- expand for each worker x layoff, then we keep t=4
by user_id: egen user_numlayoffs = total(layoffclosure_dummy) // some users may be in multiple events in separate year+quarters
replace layoffclosure_id = "ZZZ" if layoffclosure_id == "" // move blanks to the end so we can tag each layoff if user has multiple events
sort user_id layoffclosure_id
by user_id: gen user_layoff_id = _n
replace user_layoff_id = . if layoffclosure_id == "ZZZ"
sum user_numlayoffs, d
local maxeventnum `r(max)'
forvalues i=1(1)`maxeventnum' {
  expand `i' if user_numlayoffs == `i' // if user has 3 layoffs, we expand 3 times, one for each event
}
bys user_id year quarter: gen user_yq_id = _n // post-duplicate, match user-layoff id and user-year-quarter id
replace layoffclosure_id = "" if user_yq_id != user_layoff_id
replace layoffclosure_dummy = 0 if layoffclosure_id == ""

*define event time, index key RHS vars to time of displacement, define LHS
gen eventtime_qtr = . // define event time
gen qtime = (year-2010)*4+quarter
sort user_id user_yq_id qtime
gen qtime_layoff = qtime if layoffclosure_dummy == 1 // fill in missing, this is the year-quarter per user x layoff in which the layoff happens
by user_id user_yq_id: egen temp = min(qtime_layoff)
replace eventtime_qtr = qtime - temp // normalize eventtime to be 0 in year-quarter of layoff or closure event

gen flag_change_metro_m1 = 0 // equals 1 if metro is different from metro in eventtime = 0
gen metro_area_0_temp = metro_area if eventtime_qtr == 0
by user_id user_yq_id: egen metro_area_m1 = mode(metro_area_0_temp)
replace flag_change_metro_m1 = 1 if metro_area != metro_area_m1
gen naics2d_0_temp = naics2d if eventtime_qtr == 0
by user_id user_yq_id: egen naics2d_m1 = mode(naics2d_0_temp)
gen year_0_temp = year if eventtime_qtr == 0
by user_id user_yq_id: egen year_m1 = mode(year_0_temp)

*collapse to worker x layoff level
*keep t=4
keep if eventtime_qtr == 4 // ensures that the obs we have left are strictly 1-year post-layoff

*merge on average network sizes
*merge on log average yearly network size from c8 based on all degrees and bach only
preserve
use `c8_out_all', clear
keep unitid metro_area mean_N_w_metro_all
rename metro_area metro_area_m1
gen logmean_metro_all_m1 = log(mean_N_w_metro_all)
drop mean_N_w_metro_all
tempfile avgnetworksize
save `avgnetworksize', replace
restore

foreach deg in bach highest {
  rename unitid`deg' unitid
  merge m:1 metro_area_m1 unitid using `avgnetworksize'
  drop if _m == 2
  drop _m
  rename unitid unitid`deg'
  rename logmean_metro_all_m1 `deg'logmean_metro_all_m1
}

*LHS is stay, not move
gen flag_stay_metro = 1 - flag_change_metro_m1

*make binscatter
binscatter flag_stay_metro highestlogmean_metro_all_m1, msymbol(circle_hollow) legend(off) graphregion(color(white)) ytitle("Probability of Staying in Origin") xtitle("log Number of Co-Alumni in Origin") ylab(0(0.2)1)
graph export `out_scatter', replace

/**********************************************************
2. Directed Mobility Binscatter
**********************************************************/

use `c17_workerlayoffmetro_`file'', clear

*generate LHS
gen flag_in_metro = (metro_area_post == metro_area)

*collapse to school x location level
bys unitidhighest: egen school_total = total(flag_in_metro)
bys unitidhighest metro_area: egen num_chose_metro = total(flag_in_metro)
gen school_frac_metro = num_chose_metro/school_total
bys unitidhighest metro_area: keep if _n == 1

*make binscatter
binscatter school_frac_metro highestlogmean_metro_all_m1, msymbol(circle_hollow) legend(off) graphregion(color(white)) ytitle("Probability of Choosing Destination") xtitle("log Number of Co-Alumni in Destination") ylab(0(0.2)1)
graph export `dir_scatter', replace

cap log close
