/******************************
c5_workforcedynamics_masslayoffs_part1.do

Richard Jin
last modified: 6/9/24
******************************/

*Purpose: Use workforce dynamics files to identify mass layoffs in each year
*part1- see rules section below, we apply restrictions 1, 2 and 3 here, 4 in part 2

/*use adapted mass layoff definitions from Schmieder, Von Wachter and Heining (2023 AER)
Their definition is based on 30 pct. annual drop in employment, for firms with 50-plus workers
We keep the 50-plus workers requirement but have the 30 pct. drop be monthly instead

Rules:
1) 30+ percent drop in employment from previous month
2) Firm has at least 50 employees in the previous month before employment drop
3) Employment didn't increase by more than 30 percent in previous 2 years before employment drop, and
did not re-bounce in two years after drop (30 percent increase)
4) no more than 20% of the laid off employees are re-employed in the same firm within 1-year post-event
*/

*Process one year at a time for computational efficiency
*run as array job passing 1st argument `1' as the year

*Still need to figure out what to do for simultaneous positions in two MSAs
*For now, count both positions

cap log close
*change directory
cd "/yourpath"
log using "./logs/cleaning/c5_workforcedynamics_masslayoffs_part1_`1'.log", replace

*input- workforce dynamics files, 2008-2021
forvalues y = 2008(1)2021 {
  local workforce`y' "./data_raw/workforcedynamics/workforcedynamics_us_`y’.csv"
}

*output- subset of workforce dynamics files, collapsed to firm x month level, with mass layoff events based on standard (weighted) counts
local c5out`1'_count "./data_constructed/c5_masslayoffs`1'_part1_count.dta"

*output- subset of workforce dynamics files, collapsed to firm x month level, with mass layoff events based on raw counts
local c5out`1'_rawcount "./data_constructed/c5_masslayoffs`1'_part1_rawcount.dta"

*output- subset of workforce dynamics files, collapsed to firm x month level, with mass layoff events based on scaled counts
local c5out`1'_scaledcount "./data_constructed/c5_masslayoffs`1'_part1_scaledcount.dta"

/*******************
1. Setup
*******************/

*append previous two years and post two years of workforce dynamics files
local yminus1 = `1' - 1
local yminus2 = `1' - 2
local yplus1 = `1' + 1
local yplus2 = `1' + 2

*collapse to firm x month
foreach year in `yminus1' `yminus2' `1' `yplus1' `yplus2' {
  import delimited using `workforce`year'', clear
  drop country state salary duration remote* seniority job_category
  sort rcid metro_area datemonth
  foreach var in count raw_count scaled_count {
    by rcid metro_area datemonth: egen firm_`var' = total(`var')
  }
  keep rcid metro_area datemonth firm_*
  bys rcid metro_area datemonth: keep if _n == 1
  tempfile workforce_sub_`year'
  save `workforce_sub_`year'', replace
}

use `workforce_sub_`yminus2'', clear
append using `workforce_sub_`yminus1'' `workforce_sub_`1'' `workforce_sub_`yplus1'' `workforce_sub_`yplus2''
gen year = substr(datemonth,1,4)
destring year, replace
gen month = substr(datemonth,6,2)
destring month, replace
sort rcid metro_area year month
fillin rcid metro_area year month // fill in any missing records, helps calculate differences in vars when missing
tempfile workforce_fullyears
save `workforce_fullyears', replace

*create separate potential layoffs events based on each of the counts measures
foreach file in count rawcount scaledcount {
  use `workforce_fullyears', clear

  *calculate 1-year and month-month changes for adjacent years
  if "`file'" == "count" {
    local var count
  }
  else if "`file'" == "rawcount" {
    local var raw_count
  }
  else if "`file'" == "scaledcount" {
    local var scaled_count
  }

  sort rcid metro_area year month
  by rcid metro_area: gen firm_`var'_diff = firm_`var' - firm_`var'[_n-1] // month to month changes for adjacent years
  by rcid metro_area: gen firm_`var'_yrdiff = firm_`var' - firm_`var'[_n-12] // yearly changes

  *calculate percentage changes month-month and yearly
  gen firm_`var'_prev = firm_`var' - firm_`var'_diff
  gen firm_`var'_pctchange = firm_`var'_diff/firm_`var'_prev
  gen firm_`var'_yrago = firm_`var' - firm_`var'_yrdiff
  gen firm_`var'_yrpctchange = firm_`var'_yrdiff/firm_`var'_yrago

  *rule 1: tag the events in given year that had greater than 30-percent 1-month drop
  gen flag_`var'_30pctdrop = (firm_`var'_pctchange <= -0.3 & firm_`var'_pctchange != .)
  replace flag_`var'_30pctdrop = 1 if firm_`var'_yrpctchange <= -0.3 & firm_`var'_yrpctchange != .

  *rule 2: tag events in given year with at least 50 employees in previous month
  gen flag_`var'_50emp = (firm_`var'_prev >= 50)

  *rule 3: tag if neither month-month or yearly changes exceed 30 percent increase in 2 preceding years
  by rcid metro_area: gen firmmonth_id = _n // already sorted by firm and month
  gen flag_`var'_1and2 = (flag_`var'_30pctdrop == 1 & flag_`var'_50emp == 1 & year == `1')
  sort rcid metro_area flag_`var'_1and2 year month
  by rcid metro_area flag_`var'_1and2: gen firmmonthevent_id = _n // if multiple events, separately identify them
  replace firmmonthevent_id = . if year != `1' | flag_`var'_1and2 == 0
  drop flag_`var'_1and2
  sum firmmonthevent_id
  local maxeventnum `r(max)'
  gen flag_`var'_nopre = 0
  forvalues i=1(1)`maxeventnum' {
    bys rcid metro_area: egen event`i'_firmmonth_id_temp = min(firmmonth_id) if firmmonthevent_id == `i'
    by rcid metro_area: egen event`i'_firmmonth_id = max(event`i'_firmmonth_id_temp) // fill in missing values
    sort rcid metro_area year month
    by rcid metro_area: egen max_firm_pctchange = max(firm_`var'_pctchange) if firmmonth_id < event`i'_firmmonth_id
    by rcid metro_area: egen max_firm_yrpctchange = max(firm_`var'_yrpctchange) if firmmonth_id < event`i'_firmmonth_id
    gen flag_temp = 0
    replace flag_temp = 1 if (max_firm_pctchange <= 0.3 & max_firm_pctchange != .) | (max_firm_yrpctchange <= 0.3 & max_firm_yrpctchange != .)
    by rcid metro_area: egen flag`i'_`var'_nopre = max(flag_temp)
    replace flag_`var'_nopre = flag`i'_`var'_nopre if firmmonthevent_id == `i'
    drop max_firm_pctchange max_firm_yrpctchange flag_temp flag`i'_`var'_nopre event`i'_firmmonth_id_temp
  }

  *calculate percentage change from event to subsequent months and tag if no subsequent month in 2 years has a 30 percent bounceback
  gen flag_`var'_nopost = 0
  forvalues i=1(1)`maxeventnum' {
    gen firm_`var'_`i'_temp = firm_`var' if firmmonthevent_id == `i'
    sort rcid metro_area year month
    by rcid metro_area: egen firm_`var'_`i' = max(firm_`var'_`i'_temp)
    gen firm_`var'_diff_`i' = firm_`var' - firm_`var'_`i'
    gen firm_`var'_postpctch_`i' = firm_`var'_diff_`i'/firm_`var'_`i'
    by rcid metro_area: egen max_firm_postpctch = max(firm_`var'_postpctch_`i') if firmmonth_id > event`i'_firmmonth_id
    gen flag_temp = (max_firm_postpctch <= 0.3 & max_firm_postpctch != .)
    by rcid metro_area: egen flag`i'_`var'_nopost = max(flag_temp)
    replace flag_`var'_nopost = flag`i'_`var'_nopost if firmmonthevent_id == `i'
    drop max_firm_postpctch flag_temp flag`i'_`var'_nopost event`i'_firmmonth_id firm_`var'*`i' firm_`var'_`i'_temp
  }

  tempfile preclean_out_`var'
  save `preclean_out_`var'', replace
}

/*******************
2. Save output
*******************/

foreach var in count raw_count scaled_count {
  if "`var'" == "count" {
    local file count
  }
  else if "`var'" == "raw_count" {
    local file rawcount
  }
  else if "`var'" == "scaled_count" {
    local file scaledcount
  }

  *keep necessary vars only
  use `preclean_out_`var'', clear
  keep if year == `1'
  drop if metro_area == "" // exclude missing metro firms from sample
  keep rcid metro_area year month firm_`var' firm_`var'_prev flag*
  sort rcid metro_area year month
  order rcid metro_area year month firm_`var' firm_`var'_prev flag*

  *keep firm x month pairs that satisfy rules 1, 2 and 3
  keep if flag_`var'_30pctdrop == 1 & flag_`var'_50emp == 1 & flag_`var'_nopre == 1 & flag_`var'_nopost == 1
  save `c5out`1'_`file'', replace
}

cap log close
