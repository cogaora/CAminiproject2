library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic(
	ram_size : INTEGER := 32768;
	cache_size: INTEGER := 32
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
	TYPE CacheState is (idle, cread, cwrite, memread, memwrite, check_addr_w, check_addr_r);
	SIGNAL state : CacheState;
	TYPE DirtyValid is ARRAY(cache_size-1 downto 0) of std_logic_vector(0 to 0);
	TYPE TagArr is ARRAY(cache_size-1 downto 0) of std_logic_vector (5 downto 0);

	SIGNAL dirty : DirtyValid;  -- (dirty bit, valid bit)
	SIGNAL valid : DirtyValid;
	SIGNAL tags : TagArr;
	TYPE CacheStructure is ARRAY(cache_size-1 downto 0) OF STD_LOGIC_VECTOR (127 downto 0);
	TYPE MEM IS ARRAY(ram_size-1 downto 0) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL CacheBlock: CacheStructure;

	alias block_offset is s_addr(1 downto 0);
	alias set is s_addr(6 downto 2);
	alias tag is s_addr(12 downto 7);

begin

process(clock, reset)
begin
	--initalise cache and dirty/valid vector
	if (now < 1 ps)THEN
			for i in 0 to cache_size-1 loop
				CacheBlock(i) <= std_logic_vector(to_unsigned(i,128));
				dirty(i) <= "0";
				valid(i) <= "0";
			end loop;
	end if;

	if (reset'event and reset = '1') then
    		state <= idle;
    		for i in 0 to cache_size-1 loop
				CacheBlock(i) <= std_logic_vector(to_unsigned(i,128));
				dirty(i) <= "0";
				valid(i) <= "0";
			end loop;

    
  	elsif rising_edge(clock) then
		case state is
			when idle =>

				if(clock'event and clock = '1') then
				--update value of input address
					--block_offset <= s_addr(0 to 1);
		 			--set <= s_addr(2 to 6);
		 			--tag <= s_addr(7 to 12);

		 			if s_write = '1' then
		          		state <= check_addr_w;
					elsif s_read = '1' then
						state <= check_addr_r;
					else 
		         	 	state <= idle;
			 		end if;
	        	end if;

			--check if block valid and not dirty
			when check_addr_w =>
				if (valid(set) = "1") then
					if(dirty(set) = "0") then
						state <= cwrite;

					else
						state <= memwrite;
					end if;

				else
					state <= memwrite;
				end if;
			
			when cwrite =>
				CacheBlock(s_addr) <= s_writedata;
				state <= idle;

			when memwrite =>
				m_writedata <= CacheBlock(s_addr);
				valid(set) <= "0";
				dirty(set) <= "0";
				state <= cwrite;


		end case;

	end if;
end process;
end arch;