Project: "College Alumni Networks and Mobility Across Local Labor Markets"
We quantify the impact of alumni networks on the geographic mobility of job seekers for nearly 1,400 US colleges and universities.

Data:
From Revelio Labs, accessed via Wharton Research Data Services (WRDS)

Code:
'code/' provides snippets of project code, specifically Stata .do files, including cleaning and analysis

'code/cleaning/' subfolder:

c4_networksize_schoolMSAyear.do
- constructs network sizes for each school using Revelio Labs' education files and individual positions files 

c5_workforcedynamics_masslayoffs_part1.do
- identifies mass layoff events based on well-defined rules using Revelio Labs' Workforce Dynamics Files

c14_estimationsample_construct.do
- combines individual positions files, education files and user characteristics files to construct estimation sample

'code/analysis/' subfolder:

a209_mobility_binscatter.do
- descriptive analysis creating a binscatter plot

a212_nlogitstep1_ppml.do
- estimation of gravity equation via Poisson Pseudo-Maximum Likelihood

a213_nlogitstep2_logit.do
- estimation of binary logit in upper nest of nested logit model
