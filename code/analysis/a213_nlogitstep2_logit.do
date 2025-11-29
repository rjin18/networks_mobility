/*******************************************
a213_nlogitstep2_logit.do

Richard Jin
last modified: 9/19/25
*******************************************/

/*Purpose: Run 2nd step of nested logit model, which is a binary logit on 1(stay)

Source: a174

LHS is based on location in job 1-year post-displacement

models (harmonize with 1st step)- don't include any FE that are not analogous to step 1:
Recall that moving costs are 0 for stay option 
1. individual controls + institution controls, add origin FE (step 1 model 3 has origin x destination FE) + layoff year FE
2. individual controls, origin x metro FE, layoff year FE (use model 4 from step 1, has destination x sch metro FE)
3. add city x industry FE (keep model 4)
4. individual controls, origin x strata FE, layoff year FE (model 5 has destination x strata FE, origin x destination FE)

Add LPM with model 4 and then one adding school FE, and two saturated models with no school FE but with fully interacted origin x strata x industry

RHS: log network size in year of displacement

Cluster SEs at city x school level, bootstrap later 
*/

clear all
set maxvar 32767

cap log close
*change directory
cd "/yourpath"
log using "./logs/a213_nlogitstep2_logit.log", replace

*input- individual-level data
local logit_data "./data/data_constructed/a173_relocation_logit_1yrpost_data.dta"

*input- 1st step ppml logsums 
foreach mod in 1 2 3 4 5 {
  local highest_logsum_Am`mod' "./data/data_constructed/a212_nlogitstep1ppml_logsumhighest_sizem`mod'.dta"
  local bach_logsum_Am`mod' "./data/data_constructed/a212_nlogitstep1ppml_logsumbach_sizem`mod'.dta"
  local highest_logsum_Bm`mod' "./data/data_constructed/a212_nlogitstep1ppml_logsumhighest_meanm`mod'.dta"
  local bach_logsum_Bm`mod' "./data/data_constructed/a212_nlogitstep1ppml_logsumbach_meanm`mod'.dta"
}

*output- tex tables
*4 tables for each (2x) combo of: own deg highest vs. bach, networks based on number total degrees
*additional breakdown of RHS- yearly log network size (A) or log of average yearly network size (B)
local B_inst bach
local H_inst highest
foreach deg in B H {
  local `deg'_tab_all_A "./output/tables/a213_nlogit2step_logit_``deg'_inst'inst_logsizealldegrees.tex"
  local `deg'_tab_all_B "./output/tables/a213_nlogit2step_logit_``deg'_inst'inst_logmeansizealldegrees.tex"
}
local H_tab_lpmlogit_A "./output/tables/a213_nlogit2step_logitlpm_highestinst_logsizealldegrees.tex"

/**********************************************************
1. Create tables with logit regressions
**********************************************************/

/*
Versions:
1. network size based on all degrees, individual i's institution based on highest degree
2. network size based on all degrees, individual i's institution based on bach degree

RHS:
1. yearly log size
2. log of average yearly size
*/

use `logit_data', clear

*LHS is stay, not move
gen flag_stay_metro = 1 - flag_change_metro

*generate some control vars
encode sex_predicted, gen(sex_predicted_code)
encode ethnicity_predicted, gen(ethnicity_predicted_code)
gen age = year - yearborn
gen age_sq = age^2
replace instsizebach = . if instsizebach < 0
replace instsizehighest = . if instsizehighest < 0
egen city_m1xindustry = group(metro_area_m1 naics2d_m1)
egen city_m1xschoolhighest = group(metro_area_m1 unitidhighest)
egen city_m1xschoolbach = group(metro_area_m1 unitidbach)
encode school_metro_areabach, gen(school_metro_bach_code)
encode school_metro_areahighest, gen(school_metro_highest_code)
encode metro_area_m1, gen(origin)
egen cityxindustryxbachmetro = group(metro_area_m1 naics2d_m1 school_metro_bach_code)
egen cityxindustryxhighestmetro = group(metro_area_m1 naics2d_m1 school_metro_highest_code)
egen cityxindustryxbachschgroup = group(metro_area_m1 naics2d_m1 cem_strata_bach)
egen cityxindustryxhighestschgroup = group(metro_area_m1 naics2d_m1 cem_strata_highest)
egen cityxhighestmetro = group(metro_area_m1 school_metro_highest_code)
egen cityxbachmetro = group(metro_area_m1 school_metro_bach_code)
egen cityxhighestschgroup = group(metro_area_m1 cem_strata_highest)
egen cityxbachschgroup = group(metro_area_m1 cem_strata_bach)

*macros for vars
local user_controls i.sex_predicted_code i.ethnicity_predicted_code age age_sq // individual controls
local inst_controls_highest i.iclevelhighest i.instsizehighest // IPEDS controls for highest degree inst
local inst_controls_bach i.iclevelbach i.instsizebach // IPEDS controls for bach inst
local cityxindustryFE i.city_m1xindustry
local cityxindustryxbachmetroFE i.cityxindustryxbachmetro
local cityxindustryxhighestmetroFE i.cityxindustryxhighestmetro
local cityxindustryxbachschgroupFE i.cityxindustryxbachschgroup
local cityxindustryxhighestschgroupFE i.cityxindustryxhighestschgroup
local layofftimeFE i.year_m1
local schoolmetrobachFE i.school_metro_bach_code
local schoolmetrohighestFE i.school_metro_highest_code
local schoolbachFE i.unitidbach
local schoolhighestFE i.unitidhighest
local cityxhighestmetroFE i.cityxhighestmetro
local cityxbachmetroFE i.cityxbachmetro
local cityxhighestschgroupFE i.cityxhighestschgroup
local cityxbachschgroupFE i.cityxbachschgroup

drop logsum*

*Run specs
foreach owndeg in highest bach { // label RHS vars for the 2 versions
  local L`owndeg'logsize_w_metro_all_m1 A
  local L`owndeg'logmean_metro_all_m1 B
}
*1. network size based on all degrees, individual i's institution based on highest degree
foreach rhsvar in highestlogsize_w_metro_all_m1 highestlogmean_metro_all_m1 {
  merge m:1 metro_area_m1 unitidhighest using `highest_logsum_`L`rhsvar''m3'
  drop if _m == 2
  drop _m
  eststo m1_basiccontrols_`L`rhsvar'': logit flag_stay_metro `rhsvar' logsum_highest `user_controls' `inst_controls_highest' `layofftimeFE' i.origin, vce(cluster city_m1xschoolhighest) iterate(70) // individual and institutional controls, cityxindustry and time FE
  margins, dydx(`rhsvar')
  drop logsum*
  merge m:1 metro_area_m1 unitidhighest using `highest_logsum_`L`rhsvar''m4'
  drop if _m == 2
  drop _m
  eststo m1_cmetro_`L`rhsvar'': logit flag_stay_metro `rhsvar' logsum_highest `user_controls' `inst_controls_highest' `cityxhighestmetroFE' `layofftimeFE', vce(cluster city_m1xschoolhighest) iterate(70) // individual controls, school FE, cityxmetro and time FE
  margins, dydx(`rhsvar')
  eststo m1_cjcmetro_`L`rhsvar'': logit flag_stay_metro `rhsvar' logsum_highest `user_controls' `inst_controls_highest' `cityxindustryFE' `cityxhighestmetroFE' `layofftimeFE', vce(cluster city_m1xschoolhighest) iterate(70) // individual controls, school FE, cityxindustry, cityxmetro and time FE
  margins, dydx(`rhsvar')
  drop logsum*
  
  merge m:1 metro_area_m1 unitidhighest using `highest_logsum_`L`rhsvar''m5'
  drop if _m == 2
  drop _m
  eststo m1_cstrata_`L`rhsvar'': logit flag_stay_metro `rhsvar' logsum_highest `user_controls' `inst_controls_highest' `cityxhighestschgroupFE' `layofftimeFE', vce(cluster city_m1xschoolhighest) iterate(70) // individual + inst controls, cityxstrata and time FE
  margins, dydx(`rhsvar')
  drop logsum*
}

*2. network size based on all degrees, individual i's institution based on bach degree
foreach rhsvar in bachlogsize_w_metro_all_m1 bachlogmean_metro_all_m1 {
  merge m:1 metro_area_m1 unitidbach using `bach_logsum_`L`rhsvar''m3'
  drop if _m == 2
  drop _m
  eststo m2_basiccontrols_`L`rhsvar'': logit flag_stay_metro `rhsvar' logsum_bach `user_controls' `inst_controls_bach' `layofftimeFE' i.origin,vce(cluster city_m1xschoolbach) iterate(70) // individual and institutional controls, cityxindustry and time FE
  margins, dydx(`rhsvar')
  drop logsum*
  merge m:1 metro_area_m1 unitidbach using `bach_logsum_`L`rhsvar''m4'
  drop if _m == 2
  drop _m
  eststo m2_cmetro_`L`rhsvar'': logit flag_stay_metro `rhsvar' logsum_bach `user_controls' `inst_controls_bach' `cityxbachmetroFE' `layofftimeFE', vce(cluster city_m1xschoolbach) iterate(70) // individual controls, school FE, cityxmetro and time FE
  margins, dydx(`rhsvar')
  eststo m2_cjcmetro_`L`rhsvar'': logit flag_stay_metro `rhsvar' logsum_bach `user_controls' `inst_controls_bach' `cityxindustryFE' `cityxbachmetroFE' `layofftimeFE', vce(cluster city_m1xschoolbach) iterate(70) // individual controls, school FE, cityxindustry, cityxmetro and time FE
  margins, dydx(`rhsvar')
  drop logsum*
  merge m:1 metro_area_m1 unitidbach using `bach_logsum_`L`rhsvar''m5'
  drop if _m == 2
  drop _m
  eststo m2_cstrata_`L`rhsvar'': logit flag_stay_metro `rhsvar' logsum_bach `user_controls' `cityxbachschgroupFE' `layofftimeFE', vce(cluster city_m1xschoolbach) iterate(70) // individual + inst controls, cityxstrata and time FE
  margins, dydx(`rhsvar')
  drop logsum*
}

*save output
*models: basic, add city x ind and layoff time FE, add school city FE, add school FE instead of school city FE
estout m1_basiccontrols_A m1_cmetro_A m1_cjcmetro_A m1_cstrata_A using `H_tab_all_A', replace cells(b(star fmt(3)) se(fmt(3) par)) stats(N, fmt(%9.0fc) labels("Observations")) starlevels(* 0.1 ** 0.05 *** 0.01) ///
keep(highestlogsize_w_metro_all_m1 logsum_highest) varlabels(highestlogsize_w_metro_all_m1 "log Number of Co-Alumni" logsum_highest "Outside Option Value",elist(logsum_highest \hline)) end("\\") mlabels(none) collabels(none) delimiter("&")
estout m1_basiccontrols_B m1_cmetro_B m1_cjcmetro_B m1_cstrata_B using `H_tab_all_B', replace cells(b(star fmt(3)) se(fmt(3) par)) stats(N, fmt(%9.0fc) labels("Observations")) starlevels(* 0.1 ** 0.05 *** 0.01) ///
keep(highestlogmean_metro_all_m1 logsum_highest) varlabels(highestlogmean_metro_all_m1 "log Number of Co-Alumni" logsum_highest "Outside Option Value",elist(logsum_highest \hline)) end("\\") mlabels(none) collabels(none) delimiter("&")

estout m2_basiccontrols_A m2_cmetro_A m2_cjcmetro_A m2_cstrata_A using `B_tab_all_A', replace cells(b(star fmt(3)) se(fmt(3) par)) stats(N, fmt(%9.0fc) labels("Observations")) starlevels(* 0.1 ** 0.05 *** 0.01) ///
keep(bachlogsize_w_metro_all_m1 logsum_bach) varlabels(bachlogsize_w_metro_all_m1 "log Number of Co-Alumni" logsum_bach "Outside Option Value",elist(logsum_bach \hline)) end("\\") mlabels(none) collabels(none) delimiter("&")
estout m2_basiccontrols_B m2_cmetro_B m2_cjcmetro_B m2_cstrata_B using `B_tab_all_B', replace cells(b(star fmt(3)) se(fmt(3) par)) stats(N, fmt(%9.0fc) labels("Observations")) starlevels(* 0.1 ** 0.05 *** 0.01) ///
keep(bachlogmean_metro_all_m1 logsum_bach) varlabels(bachlogmean_metro_all_m1 "log Number of Co-Alumni" logsum_bach "Outside Option Value",elist(logsum_bach \hline)) end("\\") mlabels(none) collabels(none) delimiter("&")

*Now do a table with most saturated spec, show LPM for it, and then do most saturated LPM 
merge m:1 metro_area_m1 unitidhighest using `highest_logsum_Am5'
drop if _m == 2
drop _m
eststo m1_cstrata_lpm_A: reghdfe flag_stay_metro highestlogsize_w_metro_all_m1 logsum_highest `user_controls' `inst_controls_highest', absorb(`cityxhighestschgroupFE' `layofftimeFE') vce(cluster city_m1xschoolhighest) // individual + inst controls, cityxstrata and time FE
eststo m1_cstrata_sFE_lpm_A: reghdfe flag_stay_metro highestlogsize_w_metro_all_m1 logsum_highest `user_controls' `inst_controls_highest', absorb(`schoolhighestFE' `cityxhighestschgroupFE' `layofftimeFE') vce(cluster city_m1xschoolhighest) 
eststo m1_cjstrata_lpm_A: reghdfe flag_stay_metro highestlogsize_w_metro_all_m1 logsum_highest `user_controls' `inst_controls_highest', absorb(`cityxindustryxhighestschgroupFE' `layofftimeFE') vce(cluster city_m1xschoolhighest) // individual + inst controls, cityxstrata and time FE
estout m1_cstrata_A m1_cstrata_lpm_A m1_cstrata_sFE_lpm_A m1_cjstrata_lpm_A using `H_tab_lpmlogit_A', replace cells(b(star fmt(3)) se(fmt(3) par)) stats(N, fmt(%9.0fc) labels("Observations")) starlevels(* 0.1 ** 0.05 *** 0.01) ///
keep(highestlogsize_w_metro_all_m1 logsum_highest) varlabels(highestlogsize_w_metro_all_m1 "log Number of Co-Alumni" logsum_highest "Outside Option Value",elist(logsum_highest \hline)) end("\\") mlabels(none) collabels(none) delimiter("&")

cap log close
