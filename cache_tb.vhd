LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY cache_tb IS
END cache_tb;

ARCHITECTURE behavior OF cache_tb IS

    COMPONENT cache IS
        GENERIC (
            ram_size : INTEGER := 32768
        );
        PORT (
            clock : IN STD_LOGIC;
            reset : IN STD_LOGIC;

            -- Avalon interface --
            s_addr : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
            s_read : IN STD_LOGIC;
            s_readdata : OUT STD_LOGIC_VECTOR (31 DOWNTO 0);
            s_write : IN STD_LOGIC;
            s_writedata : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
            s_waitrequest : OUT STD_LOGIC;

            m_addr : OUT INTEGER RANGE 0 TO ram_size - 1;
            m_read : OUT STD_LOGIC;
            m_readdata : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
            m_write : OUT STD_LOGIC;
            m_writedata : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
            m_waitrequest : IN STD_LOGIC
        );
    END COMPONENT;

    COMPONENT memory IS
        GENERIC (
            ram_size : INTEGER := 32768;
            mem_delay : TIME := 10 ns;
            clock_period : TIME := 1 ns
        );
        PORT (
            clock : IN STD_LOGIC;
            writedata : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
            address : IN INTEGER RANGE 0 TO ram_size - 1;
            memwrite : IN STD_LOGIC;
            memread : IN STD_LOGIC;
            readdata : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
            waitrequest : OUT STD_LOGIC
        );
    END COMPONENT;

    -- test signals 
    SIGNAL reset : STD_LOGIC := '0';
    SIGNAL clk : STD_LOGIC := '0';
    CONSTANT clk_period : TIME := 1 ns;

    SIGNAL s_addr : STD_LOGIC_VECTOR (31 DOWNTO 0);
    SIGNAL s_read : STD_LOGIC;
    SIGNAL s_readdata : STD_LOGIC_VECTOR (31 DOWNTO 0);
    SIGNAL s_write : STD_LOGIC;
    SIGNAL s_writedata : STD_LOGIC_VECTOR (31 DOWNTO 0);
    SIGNAL s_waitrequest : STD_LOGIC;

    SIGNAL m_addr : INTEGER RANGE 0 TO 2147483647;
    SIGNAL m_read : STD_LOGIC;
    SIGNAL m_readdata : STD_LOGIC_VECTOR (7 DOWNTO 0);
    SIGNAL m_write : STD_LOGIC;
    SIGNAL m_writedata : STD_LOGIC_VECTOR (7 DOWNTO 0);
    SIGNAL m_waitrequest : STD_LOGIC;

BEGIN

    -- Connect the components which we instantiated above to their
    -- respective signals.
    dut : cache
    PORT MAP(
        clock => clk,
        reset => reset,

        s_addr => s_addr,
        s_read => s_read,
        s_readdata => s_readdata,
        s_write => s_write,
        s_writedata => s_writedata,
        s_waitrequest => s_waitrequest,

        m_addr => m_addr,
        m_read => m_read,
        m_readdata => m_readdata,
        m_write => m_write,
        m_writedata => m_writedata,
        m_waitrequest => m_waitrequest
    );

    MEM : memory
    PORT MAP(
        clock => clk,
        writedata => m_writedata,
        address => m_addr,
        memwrite => m_write,
        memread => m_read,
        readdata => m_readdata,
        waitrequest => m_waitrequest
    );
    clk_process : PROCESS
    BEGIN
        clk <= '0';
        WAIT FOR clk_period/2;
        clk <= '1';
        WAIT FOR clk_period/2;
    END PROCESS;

    test_process : PROCESS
    BEGIN
        -- cases that cannot happen
        -- read, miss, dirty (if dirty 1) should be sync with memory + 2) then should be in memory)
        -- read, hit, dirty (cache should be in sync with memory)
        -- write, miss, dirty (cache should be updated over memory)
        -- write, hit, dirty (cache should be in sync with memory (not possible per our fsm))

        WAIT FOR clk_period;
        REPORT "helloe";

        -- test 2 cases: write miss, not in memory and then valid read wo/ dirty
        s_addr <= "00000000000000000000100000001000";
        s_write <= '1';
        s_read <= '0';
        s_writedata <= x"AAAAAAAA";
        WAIT UNTIL rising_edge(s_waitrequest);
        -- now, read from same address and make sure it is in cache
        s_write <= '0';
        s_read <= '1';
        WAIT UNTIL rising_edge(s_waitrequest);
        ASSERT s_readdata = x"AAAAAAAA" REPORT "error" SEVERITY error;
        s_read <= '0';
        s_write <= '0';

        WAIT FOR clk_period;

        -- test case of read clean miss - not in cache nor memory
        s_addr <= "00000000000000000000000000000000";
        s_read <= '1';
        s_write <= '0';
        WAIT UNTIL rising_edge(s_waitrequest);
        -- expecting a bunch of zeros from memory
        ASSERT s_readdata = x"00000000" REPORT "error" SEVERITY error;
        -- reset both write & read signals
        s_read <= '0';
        s_write <= '0';

        WAIT;

        -- test case for 
    END PROCESS;

END;