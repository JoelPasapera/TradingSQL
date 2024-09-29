-- FOLLOW ME: https://github.com/JoelPasapera


/*

FUNCTION 1 : COPY TABLE FROM CSV

This function copies data from a specified CSV file into the 
xauusd_database table. It first drops the existing table if it 
exists and then creates a new one with the necessary columns 
to store the imported data.

Parameters:
    file_path TEXT: The full path to the CSV file from which 
    data will be imported.

Returns:
    TEXT: A success message indicating the number of rows copied 
    into the xauusd_database table.

Usage Example:
    SELECT copy_from_csv('E:\\documents\\Python\\files\\xauusd_database.csv');

Notes:
    - This function drops the existing xauusd_database table before creating a new one.
    - Ensure that the CSV file has valid data corresponding to the expected format.
    - The function handles exceptions and returns an error message if any issues occur during execution.
*/
--

-- Drop function if exists
DROP FUNCTION IF EXISTS copy_from_csv;

-- Create or replace copy_from_csv function
CREATE OR REPLACE FUNCTION copy_from_csv(file_path TEXT)
RETURNS TEXT AS $$
DECLARE
    row_count INT;
BEGIN

    -- Create the main table
    DROP TABLE IF EXISTS xauusd_database;
    CREATE TABLE IF NOT EXISTS xauusd_database (
        id serial PRIMARY KEY,
        Time TIMESTAMP NULL,
        Date VARCHAR(11) NOT NULL,
        Hour VARCHAR(6) NOT NULL,
        Open DECIMAL(6,2) NOT NULL,
        High DECIMAL(6,2) NOT NULL,
        Low DECIMAL(6,2) NOT NULL,
        Close DECIMAL(6,2) NOT NULL,
        Delete BOOLEAN NOT NULL);

    -- Copy data from a CSV file into the given table.
    EXECUTE format(
    'COPY xauusd_database (Date, Hour, Open, High, Low, Close, Delete) 
     FROM %L 
     DELIMITER '','' 
     CSV;',
    file_path
    );

    -- Get the number of rows copied
    GET DIAGNOSTICS row_count = ROW_COUNT;

    -- Return success message with row count
    RETURN format('DONE: Copied %s rows into xauusd_database', row_count);
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN format('ERROR: %s', SQLERRM);

END;
$$
LANGUAGE plpgsql;
-- Execute the function to obtain the table
SELECT copy_from_csv('E:\\data no borrar\\documentos\\Python proyecto\\Programas\\StatTrade\\HISTORICAL_DATA_XAUUSD.csv');


/*
FUNCTION 2: transform_table

This function transforms the xauusd_database table by performing 
several operations to update its structure and data. It adds a new 
column for pips, updates the timestamp, and removes unnecessary 
columns.

Returns:
    TEXT: A success message indicating that the table was transformed.

Usage Example:
    SELECT transform_table();

Notes:
    - This function modifies the existing xauusd_database table.
    - Ensure that the table contains valid data before executing this function.
    - The function handles exceptions and returns an error message if any issues occur during execution.
*/
-- Drop function if exists
DROP FUNCTION IF EXISTS transform_table;

-- Create or replace transform_table function
CREATE OR REPLACE FUNCTION transform_table()
RETURNS TEXT AS $$
BEGIN
    -- Begin a transaction
    BEGIN
        -- Add the new column 'pips' and update 'Time' in a single step
        ALTER TABLE xauusd_database ADD COLUMN pips DECIMAL(6,2);
        
        -- Update columns in one command
        UPDATE xauusd_database 
        SET 
            pips = ABS(High - Low),
            Time = to_timestamp(concat(Date, ' ', Hour), 'YYYY.MM.DD HH24:MI');

        -- Drop unnecessary columns in one command
        ALTER TABLE xauusd_database 
        DROP COLUMN Date, 
        DROP COLUMN Hour, 
        DROP COLUMN Delete;

        -- Adjust Time to the appropriate timezone
        UPDATE xauusd_database 
        SET Time = Time AT TIME ZONE 'EST' AT TIME ZONE 'America/New_York';

        -- Create a functional index to optimize queries based on HOUR and MINUTE
        CREATE INDEX IF NOT EXISTS idx_time_hour_minute ON xauusd_database (EXTRACT(HOUR FROM time), EXTRACT(MINUTE FROM time));
        CREATE INDEX IF NOT EXISTS idx_time ON xauusd_database (time);

        -- new
        -- create table with data type information
        DROP TABLE IF EXISTS column_info;
        CREATE TABLE column_info (
            table_name VARCHAR(255),
            column_name VARCHAR(255),
            precision INTEGER,
            scale INTEGER
        );
        
        -- insert the total number of digits and number of decimal places
        INSERT INTO column_info (table_name, column_name, precision, scale)
        SELECT table_name, column_name,
            numeric_precision, numeric_scale
        FROM information_schema.columns
        WHERE table_name = 'xauusd' AND column_name = 'open';
        -- new

    EXCEPTION
        WHEN OTHERS THEN
            RETURN format('ERROR: %s', SQLERRM);
    END;

    -- Return success message with row count
    RETURN ('DONE: xauusd_database table was transformed'); 
END;
$$
LANGUAGE plpgsql;

-- Execute the function to transform the table
SELECT transform_table();


--
/*

FUNCTION 3 : GET TIME AND PRICE OF ENTRY

This function retrieves the entry time and open price from the database
based on specified hour and minute values, and stores them in the 
entry_time_price_table.

Parameters:
    start_hour INT: The hour of the entry time (0-23).
    start_minute INT: The minute of the entry time (0-59).

Returns:
    TEXT: A success message indicating completion of the operation.

Usage Example:
    SELECT get_entry_time_price(8, 0);

Notes:
    - This function drops the existing entry_time_price_table before creating a new one.
    - Ensure that the database contains valid data for the specified time.

*/
--
-- Drop function if exists
DROP FUNCTION IF EXISTS get_entry_time_price;
-- Create or replace function
CREATE OR REPLACE FUNCTION get_entry_time_price(start_hour INT, start_minute INT)
RETURNS TEXT AS $$
BEGIN
    -- Refresh: Drop and create the table
    DROP TABLE IF EXISTS entry_time_price_table;
    CREATE TABLE entry_time_price_table (
        id SERIAL PRIMARY KEY, 
        entry_time TIMESTAMP,
        open_price DECIMAL(7,2)
    );
    -- Insert data into entry_time_price_table based on specified time
    EXECUTE format('INSERT INTO entry_time_price_table (entry_time, open_price) 
                    SELECT Time, Open FROM xauusd_database 
                    WHERE EXTRACT(HOUR FROM TIME) = %L AND EXTRACT(MINUTE FROM TIME) = %L 
                    ORDER BY id', start_hour, start_minute);
    -- Return success message
    RETURN ('DONE entry_time_price_table');
EXCEPTION
    WHEN OTHERS THEN
        RETURN format('ERROR: %s', SQLERRM);
END;
$$
LANGUAGE plpgsql;
-- Execute the first function to obtain entry times and prices
-- SELECT get_entry_time_price(9,0);


/*

FUNCTION 4 : GET THE TAKE PROFIT, STOP LOSS AND TYPE ORDER

This function calculates the take profit (TP) and stop loss (SL) prices based on 
the order type ('buy' or 'sell') and inserts them into the tp_sl_price_table.

Parameters:
    type VARCHAR(5): The type of order ('buy' or 'sell').
    tp INT: The take profit value to be added or subtracted from the open price.
    sl INT: The stop loss value to be added or subtracted from the open price.
    lot_size DECIMAL(3, 2): The lot size to each trade

Returns:
    TEXT: A success message indicating completion of the operation.

Usage Example:
    SELECT get_tp_sl_price('buy', 10, 5);

Notes:
    - This function drops the existing tp_sl_price_table before creating a new one.
    - Ensure that entry_time_price_table contains valid open prices before calling this function.
*/
--
-- Drop function if exists
DROP FUNCTION IF EXISTS get_tp_sl_price;

-- Create or replace function
CREATE OR REPLACE FUNCTION get_tp_sl_price(type VARCHAR(5), tp INT, sl INT, lot_size DECIMAL(3, 2))
RETURNS TEXT AS $$
BEGIN
    -- Order type validation
    IF type NOT IN ('buy', 'sell') THEN
    RAISE EXCEPTION 'Invalid order type: %', type;
    END IF;
    -- Refresh: Drop and create the table
    DROP TABLE IF EXISTS tp_sl_price_table;
    CREATE TABLE tp_sl_price_table (
        id SERIAL PRIMARY KEY,
        tp_price DECIMAL(7,2),
        sl_price DECIMAL(7,2),
        type VARCHAR(5),
        lot_size DECIMAL(3, 2)
    );

    -- Insert data into the table based on the type
    INSERT INTO tp_sl_price_table (tp_price, sl_price, type, lot_size)
    SELECT 
        CASE 
            WHEN type = 'buy' THEN open_price + tp  -- Calculate tp_price for buy
            WHEN type = 'sell' THEN open_price - tp  -- Calculate tp_price for sell
            ELSE NULL  -- This case should not happen due to earlier validation
        END AS tp_price,
        CASE 
            WHEN type = 'buy' THEN open_price - sl  -- Calculate sl_price for buy
            WHEN type = 'sell' THEN open_price + sl  -- Calculate sl_price for sell
            ELSE NULL  -- This case should not happen due to earlier validation
        END AS sl_price,
        type,
        lot_size
    FROM entry_time_price_table;  -- Select from the entire column

    -- Return success message
    RETURN 'DONE tp_sl_price_table';
EXCEPTION
    WHEN OTHERS THEN
        RETURN format('ERROR: %s', SQLERRM);
END;
$$
 LANGUAGE plpgsql;
-- Execute the second function to obtain TP/SL according to the order type
-- SELECT get_tp_sl_price('buy',10,5,0.2);


/*

FUNCTION 5 : GET THE RESULT OF THE TRADE (CLOSE PRICE, CLOSE TIME, DURATION)

This function retrieves the close price, close time and duration of a trade based on 
the entry time and the specified prices val1 and val2 where it returns the closing price 
and time when it goes out of range.

Parameters:
    entry_time TIMESTAMP: The time when the trade was entered.
    val1 DECIMAL: numerical value (minimum or maximum)
    val2 DECIMAL: numerical value (minimum or maximum)

Returns:
    TABLE: A result set containing close time, close price, and duration of the trade.

Usage Example:
    SELECT * FROM result_trade('2023-11-23 08:00:00', 2012.26, 1972.26);

Notes:
    - This function assumes that database contains valid high and low prices for trades.
    - The isolated execution of this function is for testing purposes only, since 
    this function is used in a loop later in another function. 
    - the function only returns a value when the maximum or minimum price goes out of range,
    it does not interpret whether it reached the tp or sl first.
*/
--
-- Drop if exists
DROP FUNCTION IF EXISTS result_trade;

-- Create my hit function 
CREATE OR REPLACE FUNCTION result_trade(
    entry_time TIMESTAMP,
    val1 DECIMAL,
    val2 DECIMAL
)
RETURNS TABLE (
    close_time TIMESTAMP,
    close_price DECIMAL,
    time_difference INTERVAL
)
AS $$
DECLARE
    max_value DECIMAL;
    min_value DECIMAL;
BEGIN
    -- Determine the maximum and minimum value
    max_value := GREATEST(val1, val2);
    min_value := LEAST(val1, val2);
    RETURN QUERY
    SELECT 
        time AS close_time, 
        CASE 
            WHEN high >= max_value THEN high -- SELECT 'high' IF TRUE
            WHEN low <= min_value THEN low   -- SELECT 'low' IF TRUE
            ELSE NULL                       -- OTHERWISE 'NULL'
        END AS close_price,
        time - entry_time AS time_difference
    FROM xauusd_database
    WHERE time >= entry_time AND (high >= max_value OR low <= min_value)
    ORDER BY id 
    LIMIT 1;

END;
$$
LANGUAGE plpgsql;
-- Execute the third function to obtain trade results (optional only to see the behavior of the function on individual data).
-- SELECT * FROM result_trade('2023-11-23 08:00:00', 2012.26, 1972.26);


/*

FUNCTION 6 : GET THE TRADING JOURNAL

This function performs back testing by iterating through trades recorded in 
entry_time_table and calculating results based on TP and SL prices. It updates 
the journal with trade results including exit times and utility in pips.

Returns:
    TEXT: A success message indicating completion of back testing.

Usage Example:
    SELECT run_back_testing_faster();

Notes:
   - This function drops any existing journal table before creating a new one.
   - Ensure that all referenced tables contain valid data before executing this function.
*/
--
-- drop if exists
DROP FUNCTION IF EXISTS run_back_testing_faster;
-- my function
CREATE OR REPLACE FUNCTION run_back_testing_faster()
RETURNS TEXT AS $$
DECLARE
    entry_time_v TIMESTAMP;
    tp_price_v DECIMAL;
    sl_price_v DECIMAL;
    record RECORD;
BEGIN
    -- Refresh
    DROP TABLE IF EXISTS journal;
    CREATE TABLE journal (
        id SERIAL PRIMARY KEY, 
        entry_time TIMESTAMP, 
        type VARCHAR(5),
        lot_size DECIMAL(3,2), 
        open_price DECIMAL(7,2), 
        tp_price DECIMAL(7,2), 
        sl_price DECIMAL(7,2), 
        close_price DECIMAL(7,2), 
        exit_time TIMESTAMP, 
        duration INTERVAL, 
        utility_pips DECIMAL(7,2)
    );

    -- Apply the formula iteratively
    FOR record IN 
        SELECT a.entry_time, b.tp_price, b.sl_price
        FROM entry_time_price_table AS a
        INNER JOIN tp_sl_price_table AS b ON a.id = b.id
    LOOP
        entry_time_v := record.entry_time;
        tp_price_v := record.tp_price;
        sl_price_v := record.sl_price;

        INSERT INTO journal (exit_time, close_price, duration)
        SELECT *
        FROM result_trade(entry_time_v, tp_price_v, sl_price_v);
    END LOOP;
    
    -- Joins tables updating null values
    UPDATE journal AS c
    SET 
        entry_time = a.entry_time,
        open_price = a.open_price,
        type = b.type,
        lot_size = b.lot_size,
        tp_price = b.tp_price,
        sl_price = b.sl_price
    FROM entry_time_price_table AS a
    INNER JOIN tp_sl_price_table AS b ON a.id = b.id
    WHERE c.id = a.id  -- Be sure to update the correct row in the journal.
    AND (c.entry_time IS NULL OR c.type IS NULL OR c.lot_size IS NULL OR 
        c.open_price IS NULL OR c.tp_price IS NULL OR c.sl_price IS NULL);
    
    -- Get utility column
    UPDATE journal
    SET utility_pips =
        CASE 
            -- take profit
            WHEN (type = 'buy' AND close_price > open_price) OR (type = 'sell' AND close_price < open_price) THEN ABS(open_price - tp_price)
            -- stop loss
            ELSE -ABS(open_price - sl_price)
        END;
    -- Return success message
    RETURN ('DONE journal');

EXCEPTION
    WHEN OTHERS THEN
        RETURN format('ERROR: %s', SQLERRM);
END;
$$
LANGUAGE plpgsql;
-- Execute the fourth function to perform the back testing and obtain the journal
SELECT run_back_testing_faster();


/*
FUNCTION 7: GET TRADING JOURNAL'S STATISTICS

This function calculates trading journal statistics, including total trades, 
winning trades, losing trades, total pips gained, total pips lost, pips utility, 
win rate, profit factor, maximum pips utility, and minimum pips utility.

Returns:
    TEXT: A success message indicating completion of statistics calculation.

Usage Example:
    SELECT get_journal_statistics();

Notes:
   - This function drops any existing statistics table before creating a new one.
   - Ensure that the journal table contains valid data before executing this function.
   - Win rate = (win operations / total operations ) * 100
   - Profit factor = sum of gains / sum of losses
*/
--
-- drop if exists
DROP FUNCTION IF EXISTS get_journal_statistics;
-- my function
CREATE OR REPLACE FUNCTION get_journal_statistics()
RETURNS TEXT AS $$
DECLARE
    total_trades_v INTEGER;
    win_trades_v INTEGER;
    loss_trades_v INTEGER;
    pips_gains_v INTEGER;
    pips_losses_v INTEGER;
    pips_utility_v INTEGER;
    win_rate_v VARCHAR(100);
    profit_factor_v DECIMAL;
    max_pips_utility_v INTEGER;
    min_pips_utility_v INTEGER;

BEGIN
    -- Create a new statistics table
    DROP TABLE IF EXISTS statistics;
    CREATE TABLE statistics (
        id SERIAL PRIMARY KEY,
        total_trades INTEGER,
        win_trades INTEGER,
        loss_trades INTEGER,
        pips_gains INTEGER,
        pips_losses INTEGER,
        pips_utility INTEGER,
        win_rate VARCHAR(100),
        profit_factor DECIMAL,
        max_pips_utility INTEGER,
        min_pips_utility INTEGER
    );

    -- Calculate accumulated profit using a CTE
    WITH accumulated_profit_cte AS (
        SELECT 
            utility_pips, 
            SUM(utility_pips) OVER (ORDER BY id) AS accumulated_profit 
        FROM journal
    )
    SELECT MAX(accumulated_profit), MIN(accumulated_profit) 
    INTO max_pips_utility_v, min_pips_utility_v 
    FROM accumulated_profit_cte;

    -- Calculate statistics
    SELECT MAX(id) INTO total_trades_v FROM journal; 
    SELECT COUNT(*) INTO win_trades_v FROM journal WHERE utility_pips > 0; 
    SELECT COUNT(*) INTO loss_trades_v FROM journal WHERE utility_pips < 0; 
    SELECT SUM(utility_pips) INTO pips_gains_v FROM journal WHERE utility_pips > 0; 
    SELECT ABS(SUM(utility_pips)) INTO pips_losses_v FROM journal WHERE utility_pips < 0; 
    SELECT SUM(utility_pips) INTO pips_utility_v FROM journal;

    -- Calculate win rate and profit factor
    win_rate_v := CONCAT(ROUND((((win_trades_v * 1.0) / total_trades_v) * 100),2), '%');
    profit_factor_v := ROUND(((pips_gains_v * 1.0) / pips_losses_v),2); 

    -- Insert statistics into the table
    INSERT INTO statistics (total_trades, win_trades, loss_trades, pips_gains, pips_losses, pips_utility, win_rate, profit_factor, max_pips_utility, min_pips_utility)
    VALUES (total_trades_v, win_trades_v, loss_trades_v, pips_gains_v, pips_losses_v, pips_utility_v, win_rate_v, profit_factor_v, max_pips_utility_v, min_pips_utility_v);

    -- Return success message
    RETURN ('DONE statistics');

EXCEPTION
    WHEN OTHERS THEN
        RETURN format('ERROR: %s', SQLERRM);
END;
$$
LANGUAGE plpgsql;
-- Execute the fourth function to get trading journal's statistics
SELECT get_journal_statistics();



-- main function

-- drop if exists
DROP FUNCTION IF EXISTS main;
CREATE OR REPLACE FUNCTION main(start_hour INT, start_minute INT, type_order VARCHAR(5), take_profit INT, stop_loss INT, lot_size DECIMAL(3,2)) RETURNS TEXT AS $$
BEGIN
    -- call function
    PERFORM get_entry_time_price(start_hour, start_minute);
    
    -- call function
    PERFORM get_tp_sl_price(type_order, take_profit, stop_loss, lot_size);

    -- call function
    PERFORM run_back_testing_faster();

    -- call function
    PERFORM get_journal_statistics();
    
    RETURN ('DONE: back testing completed');
    
    -- RAISE NOTICE 'TO SHOW JOURNAL RUN: SELECT * FROM journal';
    -- RAISE NOTICE 'TO SHOW JOURNAL STATISTICS RUN: SELECT * FROM statistics';

EXCEPTION
    WHEN OTHERS THEN
        RETURN format('ERROR: %s', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- use example:
SELECT main(9,0,'buy',10,5,0.2);
SELECT * FROM statistics;
SELECT * FROM journal;

