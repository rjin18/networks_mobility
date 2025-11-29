/******************************
c14_estimationsample_construct.do

Richard Jin
last modified: 5/11/25
******************************/

*Source code: c7_estimationsample_construct.do

/*Purpose: Create baseline estimation sample
Start with employment histories (2010-2019) of workers in a mass layoff or
firm closure event between 2010 and 2018 (c13_masslayoffsfirmclosures_workersample.dta)

Then merge on educational histories from c2 output

Then merge on school x MSA x year network sizes
from c4 outputs

IMPORTANT DECISION-
If we have an overlap of two consecutive periods, we keep both records and shorten the previous job start date to end right before new job
we otherwise exclude overlapping job spells

Save estimation sample as c14
*/

cap log close
*change directory
cd "/yourpath"
log using "./logs/cleaning/c14_estimationsample_construct.log", replace

*local for year of revelio data update- 2023 for now, but if we redownload data in 2025 or later, change it forward to 2024 or 2025
local lastyear 2023

*input- worker positions histories 2010-2019, in mass layoff or firm closure events based on standard (weighted) counts, raw counts, scaled counts
foreach file in count rawcount scaledcount {
  local c13_workers_`file' "./data_constructed/c13_masslayoffsfirmclosures_`file'_workersample.dta"
}

*input- user file for individual controls
local userprofile_csv "./data_raw/userprofile/individualuser_subsetvars.csv"

*input- educ histories from c2
local educJan60Dec19_clean "./data_cleaned/individualeduc_Jan60Dec19_cleaned.dta"

*input- company mapping file
local companymapping_csv "./data_raw/companymapping/company_mapping.csv"

*input- list of US schools with IPEDS unitid (which we operationalize as our school identifier)
local USschooldta "./data_constructed/SchoolCBSAMatching/schools_mapped_to_metro.dta"

*input- c4 (school x metro) network sizes, by year
forvalues y=2010(1)2019 {
  *all degrees
  local schoolXmetroX`y'_all "./data_constructed/c4_schoolmetro`y'_alldegreesnetworksize.dta"
  *bach only
  local schoolXmetroX`y'_bach "./data_constructed/c4_schoolmetro`y'_bachdegreesnetworksize.dta"
}

*intermediate output- dataset with all network sizes (for school x year x metro)
foreach degtype in all bach {
  local networksize_metro_`degtype'_allyrs "./data_constructed/c14_schoolmetro20102019_`degtype'degreesnetworksize.dta"
}

*intermediate output- dataset at worker x year level with yearly location
foreach file in count rawcount scaledcount {
  local c14_workeryear_loc_`file' "./data_constructed/c14_workeryear_location_`file'.dta"
}

*output- estimation samples (produce 3 based on the 3 c13 outputs)
foreach file in count rawcount scaledcount {
  local c14_estimationsamp_`file' "./data_constructed/c14_estimationsample_layoffsclosures_`file'.dta"
}

/**********************************************************
1. Setup- keep subsets of vars from c2,c4,c6, user profile
**********************************************************/

*list of US schools with IPEDS unitid; keep unitids and merge onto c2 later by university_name
preserve
use `USschooldta', clear
keep university_name unitid instnm iclevel instsize linkedin_metro_area // modify to include more school-level controls if desired
rename linkedin_metro_area school_metro_area
drop if unitid == .
tempfile USschools
save `USschools', replace
restore

*c2 educ file
use `educJan60Dec19_clean', clear
keep user_id university_name startdate enddate degree
drop if enddate == "" // uncompleted degrees
tempfile usereduc_abbrev
save `usereduc_abbrev', replace

*c4 files- 'all' gives us number of alums across all degrees for school s, while 'bach' gives us the number of Bachelors degrees only
*combine all years
foreach degtype in all bach {
  use `schoolXmetroX2010_`degtype'', clear
  gen year = 2010
  forvalues y=2011(1)2019 {
    append using `schoolXmetroX`y'_`degtype''
    replace year = `y' if year == .
  }
  drop if metro_area == ""

  rename N_uw N_uw_metro_`degtype'
  rename N_w N_w_metro_`degtype'
  rename logsize_uw logsize_uw_metro_`degtype'
  rename logsize_w logsize_w_metro_`degtype'

  save `networksize_metro_`degtype'_allyrs', replace
}

*user profile
import delimited using `userprofile_csv', clear
drop fullname highest_degree
tempfile userprofile_sub
save `userprofile_sub', replace

*company mapping file
import delimited using `companymapping_csv', clear
gen naics4d = floor(naics_code/100)
gen naics2d = floor(naics_code/10000)
keep rcid naics4d naics2d
tempfile companies
save `companies', replace

/*********************************************
2. Restructure worker sample to yearly level
Construct dep var
*********************************************/

/*positions file is at the userid x position level with start and end dates
we want to convert to a panel with obs for each year in which the position is present
for each user x position, create 10 obs, 1 for each year 2010-2019
if the year is contained within position's start and end dates, then keep those years,
e.g. if a user x position started in May 2011 and ended September 2014, we keep 4 obs- 2011, 2012, 2013, 2014

we remove overlapping non-transitional job spells
*/
foreach file in count rawcount scaledcount {
  use `c13_workers_`file'', replace

  di "c13 worker sample tabs: initial counts"
  cap noisily unique user_id
  cap noisily unique rcid metro_area
  cap noisily unique layoffid
  cap noisily unique closureid

  *NECESSARY CLEAN- aggregate metro areas
  replace metro_area = "los angeles metropolitan area" if metro_area == "anaheim metropolitan area"
  replace metro_area = "los angeles metropolitan area" if metro_area == "long beach metropolitan area"
  replace metro_area = "los angeles metropolitan area" if metro_area == "riverside metropolitan area"
  replace metro_area = "miami metropolitan area" if metro_area == "fort lauderdale metropolitan area"
  replace metro_area = "miami metropolitan area" if metro_area == "west palm beach metropolitan area"
  replace metro_area = "dallas metropolitan area" if metro_area == "fort worth metropolitan area"
  replace metro_area = "seattle metropolitan area" if metro_area == "tacoma metropolitan area"

  replace month_end = 12 if year_end == .
  replace year_end = `lastyear' if year_end == .
  replace yearmonth_end = (`lastyear' - 2010)*12+12 if month_end == 12 & year_end == `lastyear'

  sort user_id yearmonth_start yearmonth_end
  *change end dates for transitions- allow for up to 3 months
  by user_id: gen gap_lastend_newstart = yearmonth_end - yearmonth_start[_n+1]
  gen change_enddate_tag = (gap_lastend_newstart >= 0 & gap_lastend_newstart <= 2)
  foreach gap in 0 1 2 {
    local i = `gap'+1
    replace yearmonth_end = yearmonth_end - `i' if change_enddate_tag == 1 & gap_lastend_newstart == `gap'
  }
  replace year_end = floor((yearmonth_end-1)/12) + 2010 if change_enddate_tag == 1
  replace month_end = yearmonth_end - 12*(year_end - 2010) if change_enddate_tag == 1

  *tag if there's been a move across metro areas
  gen move_metro_tag = 0
  by user_id: gen user_obsnum = _n
  by user_id: replace move_metro_tag = 1 if metro_area != metro_area[_n-1]
  replace move_metro_tag = 0 if user_obsnum == 1
  drop user_obsnum

  *drop overlapping non-transitional job spells
  gen overlapping_spell_tag = 0
  replace overlapping_spell_tag = 1 if gap_lastend_newstart > 2 & gap_lastend_newstart != .
  by user_id: replace overlapping_spell_tag = 1 if yearmonth_start == yearmonth_start[_n-1] & gap_lastend_newstart <= 2 // overlapping short spells, e.g. both jobs start in yearmonth 15 but one ends in 17 and the other in 16
  by user_id: replace overlapping_spell_tag = 1 if overlapping_spell_tag[_n-1] == 1

  *CHANGE FROM PREVIOUS ITERATIONS OF C14- drop users if their only layoff or closure is Jan 2010, something wonky going on there
  replace layoffid = . if layoffid != . & yearmonth_end == 1
  replace closureid = . if closureid != . & yearmonth_end == 1
  gen layoffclosure_dummy = (layoffid != . | closureid != .)
  by user_id: egen has_layoffclosure = max(layoffclosure_dummy)
  keep if has_layoffclosure == 1
  drop layoffclosure_dummy has_layoffclosure

  *now convert from worker x job spell level to worker x year level

  expand 10 // create 10 duplicates of each obs, one for each year
  bys user_id position_id: gen userposition_num = _n
  gen year = 2009 + userposition_num
  drop userposition_num
  keep if year_start <= year & year_end >= year
  replace move_metro_tag = 0 if move_metro_tag == 1 & year != year_start // don't tag the years after move

  sort user_id year yearmonth_start yearmonth_end

  *drop years with overlapping non-transitional job spells
  by user_id year: egen overlapping_spell_total = total(overlapping_spell_tag)
  drop if overlapping_spell_total > 1
  drop overlapping_spell*

  *tag for if worker moved within the year
  by user_id year: gen useryear_id = _n // in transitional periods, user will have multiple jobs recorded in a year
  by user_id year: gen useryear_numobs = _N
  by user_id year: egen user_moved_inyear = max(move_metro_tag) // construction of dep var

  *drop workers that have a missing metro in any year
  gen missingmetro = (metro_area == "")
  by user_id: egen max_missingmetro = max(missingmetro)
  drop if max_missingmetro == 1
  drop missingmetro max_missingmetro

  tempfile c13_restructured_`file'
  save `c13_restructured_`file'', replace
}

/******************
3. Merges
******************/

*loop over each of the three c13 outputs (largely identical but could be slightly different due to not using the same counts measures)
foreach file in count rawcount scaledcount {
  use `c13_restructured_`file'', clear

  *get a list of users in the c13 file- makes educ merge with c2 easier and userprofile merge easier
  preserve
  keep user_id
  bys user_id: keep if _n == 1
  tempfile userlist_`file'
  save `userlist_`file'', replace
  restore

  *merge on user characteristics from user profile
  preserve
  use `userprofile_sub', clear
  di "tab: user profile merge at user level"
  merge 1:1 user_id using `userlist_`file''
  keep if _m == 3
  drop _m
  tempfile userprofile_`file'
  save `userprofile_`file'', replace
  restore
  merge m:1 user_id using `userprofile_`file'', assert(1 3) nogen

  *merge on education from c2
  preserve
  use `usereduc_abbrev', clear
  merge m:1 user_id using `userlist_`file''
  keep if _m == 3
  drop _m

  *impute age
  /*rules:
  go by min degree:
  -if min degree observed is HS, then start date of HS is 14 years old
  -if min degree observed is associate or Bach, then start date is 18 years old
  -if min degree observed is Masters, Doctor or MBA, then start date is 23 years old
  */

  gen year_start = substr(startdate,1,4)
  destring year_start, replace
  gen year_end = substr(enddate,1,4)
  destring year_end, replace

  gen degree_num = substr(degree,1,1)
  destring degree_num, replace
  bys user_id: egen mindegree = min(degree_num)
  bys user_id: egen maxdegree = max(degree_num)

  gen yearborn_temp = .
  replace yearborn_temp = year_start - 14 if mindegree == 1 & degree_num == 1
  replace yearborn_temp = year_start - 18 if (mindegree == 2 | mindegree == 3) & (degree_num == 2 | degree_num == 3)
  replace yearborn_temp = year_start - 23 if (mindegree >= 4 & mindegree != .) & (degree_num >= 4 & degree_num != .)

  bys user_id: egen yearborn = min(yearborn_temp)
  keep user_id university_name maxdegree degree degree_num yearborn year_end startdate enddate

  *define relevant educational institution for users- 1) Bachelors, 2) highest nonmissing degree
  *If multiple Bachelors degrees, only keep most recent, e.g. latest enddate
  *If degree var is missing for all degrees, then keep only most recent, e.g. latest enddate
  sort user_id degree_num enddate startdate
  by user_id degree_num: gen userdegree_id = _n
  by user_id degree_num: gen userdegree_numobs = _N
  keep if degree_num == 3 | (degree_num == maxdegree & maxdegree != .) | maxdegree == .
  keep if userdegree_id == userdegree_numobs
  gen deg_abbrev = ""
  replace deg_abbrev = "bach" if degree_num == 3
  replace deg_abbrev = "highest" if degree_num != 3
  keep user_id university_name deg_abbrev degree yearborn year_end
  reshape wide university_name degree yearborn year_end, i(user_id) j(deg_abbrev) string
  replace university_namehighest = university_namebach if university_namehighest == "" & university_namebach != ""
  replace degreehighest = degreebach if degreehighest == "" & degreebach != ""
  drop yearbornhighest degreebach
  rename yearbornbach yearborn

  *merge the school info from IPEDS based on university_name
  gen university_name = university_namebach // convert strL to str# for merge
  drop university_namebach
  merge m:1 university_name using `USschools'
  drop if _m == 2
  drop _m
  foreach var in university_name unitid instnm iclevel instsize school_metro_area {
    rename `var' `var'bach
  }
  gen university_name = university_namehighest // convert strL to str# for merge
  drop university_namehighest
  merge m:1 university_name using `USschools'
  drop if _m == 2
  drop _m
  foreach var in university_name unitid instnm iclevel instsize school_metro_area {
    rename `var' `var'highest
  }

  tempfile merged_educ_`file'
  save `merged_educ_`file'', replace
  restore

  *for each position, merge on the user's bach and highest degrees
  merge m:1 user_id using `merged_educ_`file''
  keep if _m == 3 // only keep workers with a matched education
  drop _m
  di "c14 worker sample tabs: post-education merge"
  cap noisily unique user_id
  cap noisily unique rcid metro_area
  cap noisily unique layoffid
  cap noisily unique closureid
  drop if degreehighest == "1_High School" | degreehighest == "2_Associate" // only keep workers with Bachelors degree or higher

  *drop schools that are online-only, from 2019 ipeds ic file
  gen onlineonly_highest = inlist(unitidhighest,100690,128780,154022,413413,442569,443599,450933,461023,474863,480985,493512,380465)
  gen onlineonly_bach = inlist(unitidbach,100690,128780,154022,413413,442569,443599,450933,461023,474863,480985,493512,380465)
  drop if onlineonly_highest == 1 | onlineonly_bach == 1
  drop onlineonly_highest onlineonly_bach

  *AGE RESTRICTION: only keep spells where worker was between 22 and 55 when they started
  gen age_start = year_start - yearborn
  keep if age_start >= 22 & age_start <= 55
  drop age_start

  *UPDATED TIGHTER RESTRICTION: only keep spells that started in same year or after end year of highest degree
  egen max_yearenddegree = rowmax(year_endbach year_endhighest)
  keep if year_start >= max_yearenddegree
  drop max_yearenddegree

  *intermediate output- data at worker x year level, only keep location in which they lived the longest during the year
  preserve
  gen monthsinyear = .
  gen year_yearmonth_start = (year - 2010)*12+1 // data already at yearly level so define start and endpoints
  gen year_yearmonth_end = (year - 2010)*12 + 13
  replace monthsinyear = 12 if yearmonth_start <= year_yearmonth_start & yearmonth_end >= year_yearmonth_end
  replace monthsinyear = yearmonth_end - year_yearmonth_start if yearmonth_start <= year_yearmonth_start & yearmonth_end <= year_yearmonth_end
  replace monthsinyear = year_yearmonth_end - yearmonth_start if yearmonth_start >= year_yearmonth_start & yearmonth_end >= year_yearmonth_end
  replace monthsinyear = yearmonth_end - yearmonth_start if yearmonth_start >= year_yearmonth_start & yearmonth_end <= year_yearmonth_end
  sort user_id year yearmonth_start yearmonth_end
  by user_id year: egen max_monthsinyear = max(monthsinyear)
  keep if monthsinyear == max_monthsinyear
  by user_id year: keep if _n == 1
  keep user_id year metro_area monthsinyear unitid* instnm* school_metro_area*
  save `c14_workeryear_loc_`file'', replace
  restore

  *merge on c4 network sizes for both Bachelors degree and highest degree (could be Bachelors, or missing)
  foreach deg in bach highest {
    foreach var in unitid instnm school_metro_area {
      rename `var'`deg' `var'
    }
    merge m:1 metro_area unitid instnm school_metro_area year using `networksize_metro_all_allyrs'
    drop if _m == 2
    drop _m
    foreach var in N_uw_metro_all N_w_metro_all logsize_uw_metro_all logsize_w_metro_all {
      rename `var' `deg'`var'
    }
    merge m:1 metro_area unitid instnm school_metro_area year using `networksize_metro_bach_allyrs'
    drop if _m == 2
    drop _m
    foreach var in N_uw_metro_bach N_w_metro_bach logsize_uw_metro_bach logsize_w_metro_bach {
      rename `var' `deg'`var'
    }

    foreach var in unitid instnm school_metro_area {
      rename `var' `var'`deg'
    }
  }

  *final merge- industry from company file
  merge m:1 rcid using `companies'
  drop if _m == 2
  drop _m

  tempfile c14_presave_`file'
  save `c14_presave_`file'', replace
}

/******************
4. Save output
******************/

foreach file in count rawcount scaledcount {
  use `c14_presave_`file'', clear

  *unified layoff id, in c13 part 2 we aggregate rcid metro and consecutive months in each year
  tostring layoffid, replace
  tostring closureid, replace
  gen layoffclosure_id = ""
  replace layoffid = "" if layoffid == "."
  replace closureid = "" if closureid == "."
  tostring year_end, gen(year_str)
  replace layoffclosure_id = "L" + year_str + "00" + layoffid if layoffid != ""
  replace layoffclosure_id = "C" + year_str + "00" + closureid if closureid != ""
  drop layoffid closureid year_str

  *drop unnecessary vars
  drop useryear*

  sort user_id year yearmonth_start yearmonth_end

  *save
  save `c14_estimationsamp_`file'', replace
}

cap log close
