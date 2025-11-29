/*******************************************
a212_nlogitstep1_ppml.do

Richard Jin
last modified: 7/19/25
*******************************************/

/*Purpose: Run PPML using GFW (2003) equivalence as 1st step in nlogit
construct inclusive value of outside option for each o x s combo 

Source: a191

models:
include o x s FE
1. add destination FE 
2. replace destination FE with destination x strata FE
3. drop destination x strata FE, add o x d pair FE
4. o x s, o x d, destination x metro FE
5. add back d x school strata FE instead of destination x metro to 4

RHS defined 2 ways: 1. within-school log network size (d) in year of layoff (average across workers)
2. within-school log of average network size (d), averaged across 2010-2019

Cluster SEs three way at o x d, o x s, d x s levels for beta/sigma 
But to recover beta via estimated sigma, need to bootstrap 
*/

clear all
set maxvar 32767

cap log close
*change directory
cd "/yourpath"
log using "./logs/a212_nlogitstep1_ppml.log", replace

*input- 1st step ppml
local c17_workerlayoffmetro_`file' "./data/c17_workerlayoffmetro_1yrpost.dta"

*input- individual-level data
local logit_data "./data/data_constructed/a173_relocation_logit_1yrpost_data.dta"

*input- dataset with school groupings, at unitid level
local USschoolgroups "./data/data_constructed/c25_schoolgroups_coarsenedexactmatching.dta"

*output- 1st step ppml logsums 
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
  local `deg'_tab_all_A "./output/tables/a212_nlogitppml_step1_``deg'_inst'inst_logsizealldegrees.tex"
  local `deg'_tab_all_B "./output/tables/a212_nlogitppml_step1_``deg'_inst'inst_logmeansizealldegrees.tex"
}

/**********************************************************
0. collapse to o x s x d level 
**********************************************************/

/*
Versions:
1. network size based on all degrees, individual i's institution based on highest degree
2. network size based on all degrees, individual i's institution based on bach degree
*/

*Use worker x metro level data
use `c17_workerlayoffmetro_`file'', clear

unique user_id user_yq_id
unique metro_area

*add 0.0001 to network size to account for 0s
foreach deg in bach highest {
  gen `deg'size = exp(`deg'logsize_w_metro_all_m1)
  replace `deg'size = 0 if `deg'size == .
  gen `deg'logsize = log(`deg'size+0.0001)
}

*merge on school strata
foreach deg in bach highest {
  rename unitid`deg' unitid
  merge m:1 unitid using `USschoolgroups', keepusing(cem_strata_zone_code)
  drop if _m == 2
  drop _m
  rename unitid unitid`deg'
  rename cem_strata_zone_code cem_strata_`deg'
}

*generate LHS
gen flag_in_metro = (metro_area_post == metro_area)

*collapse data 
foreach deg in highest bach {
  preserve 
  *EXCLUDE STAYERS 
  drop if metro_area_m1 == metro_area_post 
  drop if metro_area == metro_area_m1 // exclude stay destination as an option bc it is not in lower nest 
  collapse (sum) p_od`deg'=flag_in_metro (mean) `deg'logsize_metro_d_m1avg=`deg'logsize `deg'logmean_metro_d=`deg'logmean_metro_all_m1, by(metro_area_m1 metro_area unitid`deg' cem_strata_`deg' school_metro_area`deg')
  *generate some control vars
  egen dcityxschool`deg' = group(metro_area unitid`deg')
  egen dschgroup`deg' = group(metro_area cem_strata_`deg')
  egen ocityxdcity = group(metro_area_m1 metro_area)
  egen ocityxschool`deg' = group(metro_area_m1 unitid`deg')
  encode metro_area, gen(metro_area_code)
  egen dcityxschool`deg'metro = group(metro_area school_metro_area`deg')
  
  tempfile ppml_`deg'_data
  save `ppml_`deg'_data', replace
  restore 
}

*get lists of o x s
foreach deg in highest bach {
  preserve 
  collapse (sum) p_od`deg'=flag_in_metro (mean) `deg'logsize_metro_d_m1avg=`deg'logsize `deg'logmean_metro_d=`deg'logmean_metro_all_m1, by(metro_area_m1 metro_area unitid`deg' cem_strata_`deg' school_metro_area`deg')  
  drop if metro_area == metro_area_m1 
  keep metro_area_m1 unitid`deg' school_metro_area`deg' cem_strata_`deg' metro_area `deg'logsize_metro_d_m1avg `deg'logmean_metro_d
  tempfile step2_allgroups_`deg'
  save `step2_allgroups_`deg'', replace
  restore 
}

*macros for vars
local dmetroFE i.metro_area_code
local ocityxdcityFE i.ocityxdcity
local dcityxschoolhighestFE i.dcityxschoolhighest
local dcityxschoolbachFE i.dcityxschoolbach
local dcityxschoolhighestmetFE i.dcityxschoolhighestmetro
local dcityxschoolbachmetFE i.dcityxschoolbachmetro
local dschgrouphighestFE i.dschgrouphighest 
local dschgroupbachFE i.dschgroupbach 
local oxschoolhighestFE i.ocityxschoolhighest
local oxschoolbachFE i.ocityxschoolbach

/**********************************************************
1. save beta/sigma estimates and OOVs (fix SEs and estimates later)
**********************************************************/

foreach deg in bach highest {
  local L`deg'logsize_metro_d_m1avg A
  local L`deg'logmean_metro_d B
}

foreach deg in bach highest {  
  foreach rhsvar in `deg'logsize_metro_d_m1avg `deg'logmean_metro_d {
    *model 1
    use `ppml_`deg'_data', clear
    eststo m1_`deg'_`L`rhsvar'': ppmlhdfe p_od`deg' `rhsvar', absorb(i.ocityxschool`deg' `dmetroFE', savefe) vce(cluster ocityxdcity ocityxschool`deg' dcityxschool`deg') // o x s FE, d FE
    
    predict double xb_all, xb // full prediction
    preserve 
    keep metro_area __hdfe2__
    bys metro_area: keep if _n == 1
    rename __hdfe2__ dFE_hat // get destination FE 
    gen betaoversigma = _b[`rhsvar']
    tempfile predictors
    save `predictors', replace 
    restore 
    
    use `step2_allgroups_`deg'', clear 
    merge m:1 metro_area using `predictors'
    
    *compute predictions 
    gen double vhat = betaoversigma*`rhsvar' + dFE_hat 
    gen expV = exp(vhat)
    collapse (sum) expV, by(metro_area_m1 unitid`deg')
    gen logsum_`deg' = log(expV)
    keep metro_area_m1 unitid`deg' logsum_`deg'
    save ``deg'_logsum_`L`rhsvar''m1', replace
    
    *model 2
    use `ppml_`deg'_data', clear
    eststo m2_`deg'_`L`rhsvar'': ppmlhdfe p_od`deg' `rhsvar', absorb(i.ocityxschool`deg' `dschgroup`deg'FE', savefe) vce(cluster ocityxdcity ocityxschool`deg' dcityxschool`deg') // o x s FE, d x strata FE

    predict double xb_all, xb // full prediction
    preserve 
    keep metro_area cem_strata_`deg' __hdfe2__
    bys metro_area cem_strata_`deg': keep if _n == 1
    rename __hdfe2__ dstrataFE_hat // get destination x strata FE 
    gen betaoversigma = _b[`rhsvar']
    tempfile predictors
    save `predictors', replace 
    restore 
    
    use `step2_allgroups_`deg'', clear 
    merge m:1 metro_area cem_strata_`deg' using `predictors'
    
    *compute predictions 
    gen double vhat = betaoversigma*`rhsvar' + dstrataFE_hat 
    gen expV = exp(vhat)
    collapse (sum) expV, by(metro_area_m1 unitid`deg')
    gen logsum_`deg' = log(expV)
    keep metro_area_m1 unitid`deg' logsum_`deg'
    save ``deg'_logsum_`L`rhsvar''m2', replace
    
    *model 3
    use `ppml_`deg'_data', clear
    eststo m3_`deg'_`L`rhsvar'': ppmlhdfe p_od`deg' `rhsvar', absorb(i.ocityxschool`deg' `ocityxdcityFE', savefe) vce(cluster ocityxdcity ocityxschool`deg' dcityxschool`deg') // o x s FE, o x d FE
    
    predict double xb_all, xb // full prediction
    preserve 
    keep metro_area metro_area_m1 __hdfe2__
    bys metro_area metro_area_m1: keep if _n == 1
    rename __hdfe2__ odFE_hat // get origin x destination FE 
    gen betaoversigma = _b[`rhsvar']
    tempfile predictors
    save `predictors', replace 
    restore 
    
    use `step2_allgroups_`deg'', clear 
    merge m:1 metro_area metro_area_m1 using `predictors'
    
    *compute predictions 
    gen double vhat = betaoversigma*`rhsvar' + odFE_hat 
    gen expV = exp(vhat)
    collapse (sum) expV, by(metro_area_m1 unitid`deg')
    gen logsum_`deg' = log(expV)
    keep metro_area_m1 unitid`deg' logsum_`deg'
    save ``deg'_logsum_`L`rhsvar''m3', replace
    
    *model 4
    use `ppml_`deg'_data', clear
    eststo m4_`deg'_`L`rhsvar'': ppmlhdfe p_od`deg' `rhsvar', absorb(i.ocityxschool`deg' `ocityxdcityFE' `dcityxschool`deg'metFE', savefe) vce(cluster ocityxdcity ocityxschool`deg' dcityxschool`deg') // o x d FE, d x sch met FE, o x s FE

    predict double xb_all, xb // full prediction
    preserve 
    keep metro_area metro_area_m1 school_metro_area`deg' __hdfe2__ __hdfe3__
    bys metro_area metro_area_m1 school_metro_area`deg': keep if _n == 1
    rename __hdfe2__ odFE_hat // get origin x destination FE 
    rename __hdfe3__ dsmetFE_hat // get destination x sch metro FE 
    gen betaoversigma = _b[`rhsvar']
    tempfile predictors
    save `predictors', replace 
    restore 
    
    use `step2_allgroups_`deg'', clear 
    merge m:1 metro_area metro_area_m1 school_metro_area`deg' using `predictors'
    
    *compute predictions 
    gen double vhat = betaoversigma*`rhsvar' + odFE_hat + dsmetFE_hat
    gen expV = exp(vhat)
    collapse (sum) expV, by(metro_area_m1 unitid`deg')
    gen logsum_`deg' = log(expV)
    keep metro_area_m1 unitid`deg' logsum_`deg'
    save ``deg'_logsum_`L`rhsvar''m4', replace
    
    *model 5
    use `ppml_`deg'_data', clear
    eststo m5_`deg'_`L`rhsvar'': ppmlhdfe p_od`deg' `rhsvar', absorb(i.ocityxschool`deg' `ocityxdcityFE' `dschgroup`deg'FE', savefe) vce(cluster ocityxdcity ocityxschool`deg' dcityxschool`deg') // o x d FE, d x strata FE, o x s FE

    predict double xb_all, xb // full prediction
    preserve 
    keep metro_area metro_area_m1 cem_strata_`deg' __hdfe2__ __hdfe3__
    bys metro_area metro_area_m1 cem_strata_`deg': keep if _n == 1
    rename __hdfe2__ odFE_hat // get origin x destination FE 
    rename __hdfe3__ dstrataFE_hat // get destination x strata FE 
    gen betaoversigma = _b[`rhsvar']
    tempfile predictors
    save `predictors', replace 
    restore 
    
    use `step2_allgroups_`deg'', clear 
    merge m:1 metro_area metro_area_m1 cem_strata_`deg' using `predictors'
    
    *compute predictions 
    gen double vhat = betaoversigma*`rhsvar' + odFE_hat + dstrataFE_hat
    gen expV = exp(vhat)
    collapse (sum) expV, by(metro_area_m1 unitid`deg')
    gen logsum_`deg' = log(expV)
    keep metro_area_m1 unitid`deg' logsum_`deg'
    save ``deg'_logsum_`L`rhsvar''m5', replace
  }
}

*1st step estimates, models: 5 total
estout m1_highest_A m2_highest_A m3_highest_A m4_highest_A m5_highest_A using `H_tab_all_A', replace cells(b(star fmt(3)) se(fmt(3) par)) stats(N, fmt(%9.0fc) labels("Observations")) starlevels(* 0.1 ** 0.05 *** 0.01) ///
keep(highestlogsize_metro_d_m1avg) varlabels(highestlogsize_metro_d_m1avg "Log Alumni Network Size",elist(highestlogsize_metro_d_m1avg \hline)) end("\\") mlabels(none) collabels(none) delimiter("&")
estout m1_highest_B m2_highest_B m3_highest_B m4_highest_B m5_highest_B using `H_tab_all_B', replace cells(b(star fmt(3)) se(fmt(3) par)) stats(N, fmt(%9.0fc) labels("Observations")) starlevels(* 0.1 ** 0.05 *** 0.01) ///
keep(highestlogmean_metro_d) varlabels(highestlogmean_metro_d "Log Alumni Network Size",elist(highestlogmean_metro_d \hline)) end("\\") mlabels(none) collabels(none) delimiter("&")
estout m1_bach_A m2_bach_A m3_bach_A m4_bach_A m5_bach_A using `B_tab_all_A', replace cells(b(star fmt(3)) se(fmt(3) par)) stats(N, fmt(%9.0fc) labels("Observations")) starlevels(* 0.1 ** 0.05 *** 0.01) ///
keep(bachlogsize_metro_d_m1avg) varlabels(bachlogsize_metro_d_m1avg "Log Alumni Network Size",elist(bachlogsize_metro_d_m1avg \hline)) end("\\") mlabels(none) collabels(none) delimiter("&")
estout m1_bach_B m2_bach_B m3_bach_B m4_bach_B m5_bach_B using `B_tab_all_B', replace cells(b(star fmt(3)) se(fmt(3) par)) stats(N, fmt(%9.0fc) labels("Observations")) starlevels(* 0.1 ** 0.05 *** 0.01) ///
keep(bachlogmean_metro_d) varlabels(bachlogmean_metro_d "Log Alumni Network Size",elist(bachlogmean_metro_d \hline)) end("\\") mlabels(none) collabels(none) delimiter("&")

cap log close
