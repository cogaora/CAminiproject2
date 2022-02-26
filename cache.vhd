LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY cache IS
	GENERIC (
		ram_size : INTEGER := 32768;
		cache_size : INTEGER := 32
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
END cache;

ARCHITECTURE arch OF cache IS
	TYPE CacheState IS (idle, cread, cwrite, memread, memwrite, check_addr_w, check_addr_r);
	SIGNAL state : CacheState;
	TYPE DirtyValid IS ARRAY(cache_size - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(0 TO 0);
	TYPE TagArr IS ARRAY(cache_size - 1 DOWNTO 0) OF STD_LOGIC_VECTOR (5 DOWNTO 0);

	SIGNAL dirty : DirtyValid; -- (dirty bit)
	SIGNAL valid : DirtyValid; -- (valid bit)
	SIGNAL tags : TagArr;
	TYPE CacheStructure IS ARRAY(cache_size - 1 DOWNTO 0) OF STD_LOGIC_VECTOR (127 DOWNTO 0);
	TYPE MEM IS ARRAY(ram_size - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL CacheBlock : CacheStructure;

	ALIAS block_offset IS s_addr(1 DOWNTO 0);
	-- shouldn't we define that below when starting our process?
	ALIAS set IS s_addr(6 DOWNTO 2); -- here defines the index of the block we're looking at
	ALIAS tag IS s_addr(12 DOWNTO 7); -- here identifies which bblock we have from memory

BEGIN
	PROCESS (clock, reset, s_read, s_write, state, tags, valid, dirty, CacheBlock)
		VARIABLE tmp_mem_addr : INTEGER := 0;
		VARIABLE block_offset_int : INTEGER := 0;
		VARIABLE mem_bytes_offset : INTEGER := 0;
		VARIABLE set_int : INTEGER := 0;
	BEGIN
		-- load the block offset as an integer from the block signal above (easier to access cache mem)
		block_offset_int := to_integer(unsigned(block_offset));
		set_int := to_integer(unsigned(set));

		--initalise cache and dirty/valid vector
		IF (now < 1 ps) THEN
			FOR i IN 0 TO cache_size - 1 LOOP
				CacheBlock(i) <= STD_LOGIC_VECTOR(to_unsigned(i, 128));
				dirty(i) <= "0";
				valid(i) <= "0";
			END LOOP;
		END IF;

		-- if reset, re-init cache & bits
		IF (reset'event AND reset = '1') THEN
			state <= idle;
			-- iterate through cache blocks to reset
			FOR i IN 0 TO cache_size - 1 LOOP
				CacheBlock(i) <= STD_LOGIC_VECTOR(to_unsigned(i, 128));
				dirty(i) <= "0";
				valid(i) <= "0";
			END LOOP;
		ELSIF rising_edge(clock) THEN
			CASE state IS
					-- starting in default state
				WHEN idle =>
					s_waitrequest <= '1'; -- something is happening signal it to cache operator?

					IF (clock'event AND clock = '1') THEN
						--update value of input address
						--block_offset <= s_addr(0 to 1);
						--set <= s_addr(2 to 6);
						--tag <= s_addr(7 to 12);

						IF s_write = '1' THEN
							state <= check_addr_w;
						ELSIF s_read = '1' THEN
							state <= check_addr_r;
						ELSE
							s_waitrequest <= '0'; -- nothing is happening anymore
							state <= idle;
						END IF;
					END IF;

					-- verify if we have a valid address for reading from memory
				WHEN check_addr_r =>
					IF (valid(set_int) = "1") AND (tags(set_int) = tag) THEN
						-- hit
						-- start reading from cache and writing to the output read data vector
						-- each block stores 16 bytes of data, i.e. 4 words, we wish to access 1 word
						-- i.e. 4 bytes of data - and put it into our readdata signal
						-- block_offset_int goes from 0 to 3, accessing lower word is 31 downto 0
						-- accessing 4th word is 127 down to 96
						s_readdata <= CacheBlock(set_int)((32 * (block_offset_int + 1)) - 1 DOWNTO 32 * block_offset_int);
						-- done reading go back to idle state after returning data
						s_waitrequest <= '0';
						state <= idle;
					ELSIF dirty(set_int) = "1" THEN
						-- dirty
						-- write back to memory
						state <= memwrite;
					ELSIF valid(set_int) = "0" THEN
						-- not dirty, but tag not valid, should read data from memory (and load it in cache)
						state <= memread;
					ELSE
						-- means there was a miss, but data is clean 
						-- should request data from memory and load it to cache
						state <= check_addr_r;
					END IF;

				WHEN cread =>
					state <= idle;

				WHEN memread =>
					-- memory ready to read more
					IF m_waitrequest = '1' THEN
						-- give memory an address to read from, using the lower 15 bytes of the address
						m_addr <= (to_integer(unsigned(s_addr(14 DOWNTO 0)))) + mem_bytes_offset;
						m_read <= '1';
						m_write <= '0';
						state <= memread;
					ELSIF m_waitrequest = '0' AND mem_bytes_offset > 3 THEN
						-- have completed reading 1 word from memory
						s_readdata <= CacheBlock(set_int)((32 * (block_offset_int + 1)) - 1 DOWNTO 32 * block_offset_int);
						-- update tag in cache memory for the block
						tags(set_int) <= tag;
						-- update clean & dirty tags
						dirty(set_int) <= "0";
						valid(set_int) <= "1";

						-- done reading from memory & added retrieved data from memory to cache
						s_waitrequest <= '0';
						-- done reading & writing from memory
						m_write <= '0';
						m_read <= '0';
						mem_bytes_offset := 0;
						-- go back to idle state until next request
						state <= idle;
					ELSIF m_waitrequest = '0' AND mem_bytes_offset <= 3 THEN
						-- still reading the same word from memory
						-- retrieve 8 bits from memory (sending 1 byte at a time)
						-- and put them in cache using the mem_bytes_offset 
						-- reading the nth word in memory, 127 downto 96 for example
						-- first 127 downto 120, second 119 down to 112, third 111 down to 104
						-- fourth 103 down to 96
						-- get tmp address to find in cache block right byte
						tmp_mem_addr := (32 * block_offset_int) + 8 * mem_bytes_offset;
						CacheBlock(set_int)(tmp_mem_addr + 7 DOWNTO tmp_mem_addr) <= m_readdata;
						-- increment cache block offset
						mem_bytes_offset := mem_bytes_offset + 1;
						state <= memread;
					ELSE
						-- memory not ready to read more, wait until then
						state <= memread;
					END IF;

					--check if block valid and not dirty
				WHEN check_addr_w =>
					IF (valid(set_int) = "1") THEN
						IF (dirty(set_int) = "0") THEN
							state <= cwrite;
						ELSE
							state <= memwrite;
						END IF;

					ELSE
						state <= memwrite;
					END IF;

				WHEN cwrite =>
					CacheBlock(set_int * 128 + mem_bytes_offset) <= s_writedata;
					valid(set_int) <= "1";
					dirty(set_int) <= "1";
					state <= idle;

				WHEN memwrite =>
					valid(set_int) <= "0";
					m_writedata <= CacheBlock(set_int * 128 + mem_bytes_offset);
					valid(set_int) <= "1";
					dirty(set_int) <= "0";
					state <= cwrite;
			END CASE;

		END IF;
	END PROCESS;
END arch;