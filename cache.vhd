library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic(
	ram_size : INTEGER := 32768;
	cache_size: INTEGER := 32;
);
port(
	clock : in std_logic;
	reset : in std_logic;
	
	-- Avalon interface --
	s_addr : in std_logic_vector (31 downto 0);
	s_read : in std_logic;
	s_readdata : out std_logic_vector (31 downto 0);
	s_write : in std_logic;
	s_writedata : in std_logic_vector (31 downto 0);
	s_waitrequest : out std_logic; 
    
	m_addr : out integer range 0 to ram_size-1;
	m_read : out std_logic;
	m_readdata : in std_logic_vector (7 downto 0);
	m_write : out std_logic;
	m_writedata : out std_logic_vector (7 downto 0);
	m_waitrequest : in std_logic
);
end cache;

architecture arch of cache is
	TYPE CacheState is (idle, read, write, memread, memwrite);
	SIGNAL state : CacheState;
	TYPE CacheStructure is ARRAY(cache_size-1 downto 0) OF STD_LOGIC_VECTOR (154 downto 0);
	TYPE MEM IS ARRAY(ram_size-1 downto 0) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
begin

process(clock, reset)
begin
	if (reset = '1') then
    		state <= idle;
    
  	elsif rising_edge(clock) then
		case state is
			when idle =>
			
			if s_write = '1' AND  then
          			state <= write;
			elsif
        		elsif s_read = '1' then
				state <= read;
			else 
         	 		state <= idle;
        		end if;
			
			when write =>
			
			
        
        
		 
end process;



end arch;