/ Load financial benchmark data from q binary table files for the 10_5 data set.
DATAPATH:"/Users/tianxin/projects/nyu/ms2/independent_study/data/financial/10_5";

paths:` sv/:(hsym `$DATAPATH),/:`$("base.bin";"price.bin";"split.bin";"dividend.bin");
files:`base`price`split`dividend!paths;

base:get files`base;
base:`Id`Ex`Descr`SIC`SPR`Cu`CreateDate xcol base;

price:get files`price;
price:`Id`TradeDate`HighPrice`LowPrice`ClosePrice`OpenPrice`Volume xcol price;

split:get files`split;
split:`Id`SplitDate`EntryDate`SplitFactor xcol split;

dividend:get files`dividend;
dividend:`Id`XdivDate`DivAmt`AnnounceDate xcol dividend;

/ deterministic sets and ranges required for repeatable q/l comparisons
stock10:10#base`Id;
stock1000:base`Id;
SP500:base`Id;
Russell2000:base`Id;

/ Use date offsets instead of date literals. l parses far-future date literals
/ differently from kdb+, while `date$integer is portable between both engines.
startYear10:`date$6057;         / 2016.08.01
/ adding to date here to deal easily with monetdb
endYear10:startYear10 + 365 * 10;
startYear10Plus2:startYear10 + 365 * 2;
start300Days:`date$6057;        / 2016.08.01
end300Days:start300Days + 300;
startPeriod:`date$6057;         / 2016.08.01
endPeriod:`date$6456;           / 2017.09.04
start6Mo:`date$6057;            / 2016.08.01
end6Mo:start6Mo + 6 * 31;
maxTradeDate:exec max TradeDate from price;
maxTradeDateMinusYear:maxTradeDate-365;
maxTradeDateMinus3Years:`date$6210; / 2017.01.01

getMonth:{1 + (`month$x) mod 12};
getYear:{`year$x};
firstDateOfYear:{`date$`month$d-30*-1+getMonth d:`date$`month$x};
getWeek:{1 + floor (x - firstDateOfYear x)%7};

/ type casting to wrap annoying type info loss for empty grouped tables
float:{`float$x}
