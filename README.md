# TradingSQL
this code is written in postgresql, the main function is called “main” and requires parameters such as take profit, stop loss, entry time, lotaje and order type to work. 

ATTENTION:
in the code you will find a path like this “E:\\documents\\Python\\files\\xauusd_database.csv” you must replace this with the absolute path of the csv file. 
Remember, the absolute path of a file is the directory + the name of the file where it is located. Remember also to put this: '\\' , when separating each directory so that postgresql interprets it well.


you just have to be careful with this aspect of referencing the csv file well

after executing all the code, just run this to test simple strategies in gold 

-- use example:
SELECT main(9,0,'buy',10,5,0.2);
SELECT * FROM statistics;
SELECT * FROM journal;

here the 9 refers to the time of entry
here the 0 refers to minute 0 (you can replace it with 10 which could be the time 9:10 am)
here the 10 refers to the number of pips for take profit
here the 5 refers to the amount of pips for stop loss
here the 0.2 refers to the lotaje (this does not modify results, it is just for aesthetics)

Clarifications:
The time zone is in new york zone considering the time changes UTC-5 and UTC-4 both winter and summer when it changes in 1 hour. 
the parameters are fixed, the same parameters are applied every time you operate. 
