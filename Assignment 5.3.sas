OPTIONS LS = 80 NODATE NOCENTER;

LIBNAME CRSP "Q:\Data-ReadOnly\CRSP\";
LIBNAME COMP "Q:\Data-ReadOnly\Comp\";
LIBNAME A5 "Q:\Scratch\lyin37\Assignment 5";

DATA A5.funda;
set COMP.funda;
If indfmt = 'INDL' and datafmt = 'STD' and popsrc = 'D' and fic = 'USA' and consol = 'C' and year(datadate) >= 1970 
	and year(datadate) <=2015;

CUSIP = substr(CUSIP, 1, 8);
FYear = Year(datadate);
DLC = DLC*1000000;
DLTT = DLTT*1000000;
F = DLC + 0.5*DLTT;
Year = FYear + 1;
DATE = datadate;

keep GVKEY CUSIP FYear Year F;
label F = "Face Value of Debt";
Run;

DATA A5.DSF_Read;
set CRSP.dsf;
keep CUSIP DATE PRC SHOROUT RET E FYEAR;
SHROUT = SHROUT*1000;
E = ABS(PRC)*SHROUT;
keep CUSIP DATE PRC SHROUT RET E;
label E = "Market Capitalization";
Run;

DATA A5.DSF_Year;
set A5.DSF_Read;
FYear = Year(Date);
keep CUSIP FYear E DATE;
Run;

Proc Sort data = A5.DSF_Year;
by CUSIP FYear;
Run;

Data A5.DSF_Mod;
set A5.DSF_Year;
by CUSIP FYear;
if last.FYear;
Year = FYear + 1;
Run;

PROC SQL;
CREATE TABLE A5.dsf As
SELECT CUSIP, YEAR(date) as FYear, EXP(SUM(LOG(1+RET))) - 1 As annret, DATE, STD(ret)*SQRT(250) as sigmae, Year(date)+1 as Year
FROM A5.DSF_Read
GROUP BY cusip, Year, FYear;
QUIT;

Proc sort data = A5.DSF;
by CUSIP Year;
Run;

Proc sort data = A5.Funda;
by CUSIP Year;
Run;

DATA A5.DSF_Funda;
merge A5.dsf(IN = A) A5.Funda(IN = B) A5.DSF_Mod(IN = C);
by CUSIP Year;
if A and B and C;
label E = "Market Capitalization"
	  sigmae = "Annual Volatility"
	  annret = "Annual Return"
	  F = "Default Boundary";
keep CUSIP FYear Year DATE annret sigmae E F;
Run;

PROC IMPORT DATAFILE = "P:\SAS Files\Assignment 5\DAILYFED.csv" OUT = A5.RISKFREE DBMS = CSV REPLACE;
GETNAMES = YES;
Run;

DATA A5.DAILYFED;
SET A5.RISKFREE;
KEEP DATE DTB3 R YEAR;
R = LOG(1+DTB3/100);
YEAR = YEAR(DATE);
If R = . then delete;
Run;

Proc Sort NODUPKEY data = A5.DAILYFED;
by Year;
Run;

Proc Sort data = A5.DSF_Funda;
by Year;
Run;

DATA A5.DF_RiskFree;
merge A5.DSF_Funda(IN = A) A5.DAILYFED(IN = B);
by Year;
if A and B;
if F = . then delete;
if E = . then delete;
if sigmae = . then delete;
if F = 0 then delete;
if E = 0 then delete;
if sigmae = 0 then delete;
V = E + F;
sigmav = sigmae;
Run;

Proc sort data = A5.DF_RiskFree;
By CUSIP YEAR;
Run;

DATA A5.KMV;
Year = 0;
Run;

PROC PRINTTO LOG = "P:\SAS Files\Assignment 5\Assignment 5.3\Method3.log" NEW;
Run;

%macro iterationV(y);
DATA DF_RF;
SET A5.DF_RiskFree;
If Year = &y;
Run;

PROC SORT data = DF_RF;
by CUSIP DATE;
Run;

DATA KMVRecord;
LENGTH CUSIP $ 8;
CUSIP = "";
Run;

%do i = 1 %to 11;

PROC MODEL DATA = DF_RF NOPRINT;
ENDOGENOUS V;
EXOGENOUS E F R sigmav;
E = V*probnorm((log(V/F) + (R + sigmav*sigmav/2)*1)/(sigmav*sqrt(1)))-exp(-R*1)*F*probnorm((log(V/F) + (R + sigmav*sigmav/2)*1)/(sigmav*sqrt(1)) - sigmav*sqrt(1));
solve V / out = A5.V_iter MAXITER = 300 MAXERRORS = 10000 CONVERGE = 1E-4;
by CUSIP DATE YEAR;
Run;
QUIT;

DATA DF_RF;
SET DF_RF;
Drop V;
Run;

DATA A5.V_iter;
Merge DF_RF(IN = A) A5.V_iter(IN = B);
by CUSIP DATE;
if A and B;
Run;

DATA A5.V_iter;
SET A5.V_iter;
IF CUSIP = LAG1(CUSIP) THEN AVGRET = (V - LAG1(V))/LAG1(V);
by CUSIP;
IF FIRST.CUSIP THEN AVGRET = .;
RUN;

PROC SQL;
CREATE TABLE A5.V_sol AS
SELECT CUSIP, YEAR, DATE, V, STD(AVGRET)*SQRT(250) AS sigmav_new, sigmav
FROM A5.V_iter
GROUP BY CUSIP;
QUIT;

PROC SORT data = A5.V_sol;
by CUSIP DATE;
RUN;

PROC SORT data = A5.V_iter;
by CUSIP DATE;
RUN;

DATA Diff;
Merge A5.V_iter(IN = A) A5.V_sol(IN = B);
by CUSIP DATE;
if A and B;
absv = ABS(sigmav_new - sigmav);
if absv < 0.001 and absv NE . THEN RECORD = 1;
Run;

DATA A5.V_Final;
set Diff;
If RECORD = 1;
ASSETVOL = sigmav_new;
Run;

DATA A5.V_Final;
Set A5.V_Final;
by CUSIP;
if LAST.CUSIP;
Run;

DATA KMVRecord;
MERGE KMVRecord A5.V_Final;
by CUSIP;
/*DROP sigmav AVGRET DATE;*/
Run;

DATA DF_RF;
set Diff;
if RECORD NE 1;
sigmav = sigmav_new;
drop sigmav_new;
Run;

PROC SORT data = DF_RF;
by CUSIP DATE;
Run;

%end;

DATA A5.KMV;
MERGE A5.KMV KMVRecord;
by Year;
If YEAR = 0 OR CUSIP = "" THEN DELETE;
DROP sigmav_new;
Run;

%mend;

/*DATA A5.KMV;*/
/*SET A5.KMV;*/
/*IF Year = 1974 then delete;*/
/*Run;*/

%macro InterateAll;
%do j = 1974 %to 2016;
%iterationV(&j);
%end;
%mend;

%InterateAll

PROC PRINTTO;
RUN;


LIBNAME M2 "P:\SAS Files\Assignment 5\Assignment 5.2";

/*GEt Method 1 & Method 2 DD&PD*/
DATA A5.M1M2;
SET M2.ddpd_merge;
DD_M1 = DD3;
PD_M1 = PD3;
DD_M2 = DD_DS;
PD_M2 = PD_DS;
drop DD1 PD1 DD2 PD2 DD3 PD3 DD_DS PD_DS;
Run; 

DATA A5.Method3;
Set A5.KMV;
DD_M3 = (log(V/F) + (ANNRET - (ASSETVOL**2)/2))*1/(ASSETVOL*sqrt(1));
PD_M3 = probnorm(-DD3);
Run;

PROC SORT data = A5.M1M2;
by CUSIP YEAR;
Run;

PROC SORT data = A5.Method3;
by CUSIP YEAR;
Run;

DATA A5.AllDATA;
merge A5.M1M2(IN = A) A5.Method3(IN = B);
by CUSIP YEAR;
if A and B;
Run;

%let DD_var = DD_M1 DD_M2 DD_M3;
%let PD_var = PD_M1 PD_M2 PD_M3;

PROC CORR data = A5.AllDATA;
var &DD_var;
TITLE 'Correlation for DD using All 3 Methods';
Run;

PROC CORR data = A5.AllDATA;
var &PD_var;
TITLE 'Correlation for PD using All 3 Methods';
Run;

PROC MEANS data = A5.AllDATA n mean p25 p50 p75 std min max;
var &DD_var &PD_var;
by Year;
title 'Discriptive Statistics of all DD and PD';
OUTPUT out = A5.DDPDStat mean = DD1_m DD2_m DD3_m PD1_m PD2_m PD3_m
						 p25 = DD1_p25 DD2_p25 DD3_p25 PD1_p25 PD2_p25 PD3_p25
						 p50 = DD1_p50 DD2_p50 DD3_p50 PD1_p50 PD2_p50 PD3_p50
						 p75 = DD1_p75 DD2_p75 DD3_p75 PD1_p75 PD2_p75 PD3_p75;
Run;


%let dd1var = DD1_m DD1_p25 DD1_p50 DD1_p75;
%let dd2var = DD2_m DD2_p25 DD2_p50 DD2_p75;
%let dd3var = DD3_m DD3_p25 DD3_p50 DD3_p75;
%let label = "mean" "p25" "p50" "p75";

%macro graph_dd_compare;

%do i = 1 %to 4;
%let plotdd3 = %qscan(&dd1var, &i, %str(" "));
%let plotdd2 = %qscan(&ddd2var, &i, %str(" "));
%let plotdd3 = %qscan(&ddd2var, &i, %str(" "));
%let varlabel = %qscan(&label, &i, %str(" "));

proc sgplot data = A5.DDPDStat;
	series x = Year y = &plotdd3;
	series x = Year y = &plotdd2;
	series x = Year y = &plotdd3;
	xaxis label = 'Year';
	label &plotdd1 = "Distance to Default method1 - " &varlabel
		  &plotdd2 = "Distance to Default method2 - " &varlabel
		  &plotdd3 = "Distance to Default method3 - " &varlabel;	
	title 'Comparision of DD using all 3 methods - &varlabel';
run;

%end;
%mend;

%graph_dd_campare;
