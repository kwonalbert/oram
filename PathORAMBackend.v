
//==============================================================================
//	Section:	Includes
//==============================================================================
`include "Const.vh"
//==============================================================================

//==============================================================================
//	Module:		PathORAMBackend
//	Desc:		The stash, AES, address generation, and throughput back-pressure 
//				logic (e.g., dummy access control, R^(E+1)W pattern control)
//==============================================================================

module PathORAMBackend(
	Clock, FastClock, Reset,

	Command, PAddr, CurrentLeaf, RemappedLeaf, 
	CommandValid, CommandReady,

	LoadData, 
	LoadValid, LoadReady,

	StoreData,
	StoreValid, StoreReady,
	
	DRAMCommandAddress, DRAMCommand, DRAMCommandValid, DRAMCommandReady,
	DRAMReadData, DRAMReadDataValid, DRAMReadDataReady,
	DRAMWriteData, DRAMWriteDataValid, DRAMWriteDataReady
	);
	
	//------------------------------------------------------------------------------
	//	Parameters & Constants
	//------------------------------------------------------------------------------

	`include "PathORAM.vh";
	`include "DDR3SDRAM.vh";
	`include "AES.vh";
	`include "Stash.vh";
	
	`include "StashLocal.vh"
	`include "DDR3SDRAMLocal.vh"
	`include "BucketLocal.vh"
	`include "BucketDRAMLocal.vh"
	`include "PathORAMBackendLocal.vh"
	`include "SHA3Local.vh"
	
	//--------------------------------------------------------------------------
	//	System I/O
	//--------------------------------------------------------------------------
		
  	input 					Clock, FastClock, Reset;
	
	//--------------------------------------------------------------------------
	//	Frontend Interface
	//--------------------------------------------------------------------------

	input	[BECMDWidth-1:0] Command;
	input	[ORAMU-1:0]		PAddr;
	input	[ORAML-1:0]		CurrentLeaf; // If Command == Append, this is XX 
	input	[ORAML-1:0]		RemappedLeaf;
	input					CommandValid;
	output 					CommandReady;

	// TODO set CommandReady = 0 if LoadDataReady = 0 (i.e., the front end can't take our result!)
	
	output	[FEDWidth-1:0]	LoadData;
	output					LoadValid;
	input 					LoadReady;

	input	[FEDWidth-1:0]	StoreData;
	input 					StoreValid;
	output 					StoreReady;
	
	//--------------------------------------------------------------------------
	//	DRAM Interface
	//--------------------------------------------------------------------------

	output	[DDRAWidth-1:0]	DRAMCommandAddress;
	output	[DDRCWidth-1:0]	DRAMCommand;
	output					DRAMCommandValid;
	input					DRAMCommandReady;
	
	input	[DDRDWidth-1:0]	DRAMReadData;
	input					DRAMReadDataValid;
	output					DRAMReadDataReady;
	
	output	[DDRDWidth-1:0]	DRAMWriteData;
	output					DRAMWriteDataValid;
	input					DRAMWriteDataReady;

	//--------------------------------------------------------------------------
	//	Wires & Regs
	//--------------------------------------------------------------------------
	
	// Backend - CC

	wire 	[DDRDWidth-1:0]	BE_DRAMWriteData, BE_DRAMReadData;
	wire					BE_DRAMWriteDataValid, BE_DRAMWriteDataReady;
	wire					BE_DRAMReadDataValid, BE_DRAMReadDataReady;	

	// CC - AES

    wire 	[DDRDWidth-1:0]	AES_DRAMWriteData, AES_DRAMReadData;
    wire 	[DDRMWidth-1:0]	AES_DRAMWriteMask;
    wire					AES_DRAMWriteDataValid, AES_DRAMWriteDataReady;
    wire					AES_DRAMReadDataValid, AES_DRAMReadDataReady;	

	// REW
	
	wire    [ORAMU-1:0]		ROPAddr;
	wire	[ORAML-1:0]		ROLeaf;
	wire                    REWRoundDummy;
    wire                    DRAMInitComplete;
	
	// integrity verification
	
	wire 					IVStart, IVDone, IVRequest, IVWrite;
	wire 	[PathBufAWidth-1:0]	IVAddress;
	wire 	[DDRDWidth-1:0]  DataFromIV, DataToIV;
	wire  					IVReady_BktOfI, IVDone_BktOfI;
	
	//--------------------------------------------------------------------------
	//	The Stash
	//--------------------------------------------------------------------------

	StashTop #(				.ORAMB(					ORAMB),
							.ORAMU(					ORAMU),
							.ORAML(					ORAML),
							.ORAMZ(					ORAMZ),
							.ORAMC(					ORAMC),
							.ORAME(					ORAME),
							
							.Overclock(				Overclock),
							.EnableAES(				EnableAES),
							.EnableREW(				EnableREW),
							.EnableIV(				EnableIV),
							
							.FEDWidth(				FEDWidth),
							.BEDWidth(				BEDWidth),							
							.DDR_nCK_PER_CLK(		DDR_nCK_PER_CLK),
							.DDRDQWidth(			DDRDQWidth),
							.DDRCWidth(				DDRCWidth),
							.DDRAWidth(				DDRAWidth),
							.IVEntropyWidth(		IVEntropyWidth))
			stash_bkend (	.Clock(					Clock),
							.Reset(					Reset),
							
							.Command(				Command),
							.PAddr(					PAddr),
							.CurrentLeaf(			CurrentLeaf),
							.RemappedLeaf(			RemappedLeaf),
							.CommandValid(			CommandValid),
							.CommandReady(			CommandReady),
							.LoadData(				LoadData),
							.LoadValid(				LoadValid),
							.LoadReady(				LoadReady),
							.StoreData(				StoreData),
							.StoreValid(			StoreValid),
							.StoreReady(			StoreReady),
							
							.DRAMCommandAddress(	DRAMCommandAddress),
							.DRAMCommand(			DRAMCommand),
							.DRAMCommandValid(		DRAMCommandValid),
							.DRAMCommandReady(		DRAMCommandReady),			

							.DRAMReadData(			BE_DRAMReadData),
							.DRAMReadDataValid(		BE_DRAMReadDataValid),
							.DRAMReadDataReady(		BE_DRAMReadDataReady),
							
							.DRAMWriteData(			BE_DRAMWriteData),
							.DRAMWriteDataValid(	BE_DRAMWriteDataValid),
							.DRAMWriteDataReady(	BE_DRAMWriteDataReady),
							
                            .ROPAddr(               ROPAddr),
							.ROLeaf(				ROLeaf),
							.REWRoundDummy(			REWRoundDummy),
							.DRAMInitComplete(		DRAMInitComplete));							
	
	//----------------------------------------------------------------------
	//	Integrity Verification (REW ORAM only)
	//----------------------------------------------------------------------
	
	generate if (EnableREW) begin:CC
		CoherenceController #(.DDR_nCK_PER_CLK(		DDR_nCK_PER_CLK),
							.DDRDQWidth(			DDRDQWidth),
							.DDRCWidth(				DDRCWidth),
							.DDRAWidth(				DDRAWidth),
							
							.ORAMB(					ORAMB),
							.ORAMU(					ORAMU),
							.ORAML(					ORAML),
							.ORAMZ(					ORAMZ),
							.ORAMC(					ORAMC),
							.ORAME(					ORAME),
							
							.Overclock(				Overclock),
							.EnableAES(				EnableAES),
							.EnableREW(				EnableREW),
							.EnableIV(				EnableIV))
							
				cc(			.Clock(					Clock),
							.Reset(					Reset),
									
							.ROPAddr(               ROPAddr),
							.REWRoundDummy(			REWRoundDummy),
							
							.FromDecData(			AES_DRAMReadData), 
							.FromDecDataValid(		AES_DRAMReadDataValid), 	
							.FromDecDataReady(		AES_DRAMReadDataReady),	// TODO remove
							
							.ToEncData(				AES_DRAMWriteData), 
							.ToEncDataValid(		AES_DRAMWriteDataValid), 
							.ToEncDataReady(		AES_DRAMWriteDataReady),	

							.ToStashData(			BE_DRAMReadData),
							.ToStashDataValid(		BE_DRAMReadDataValid), 
							.ToStashDataReady(		BE_DRAMReadDataReady),

							.FromStashData(			BE_DRAMWriteData), 
							.FromStashDataValid(	BE_DRAMWriteDataValid), 
							.FromStashDataReady(	BE_DRAMWriteDataReady),
							
							.IVStart(				IVStart),
							.IVDone(				IVDone),
							.IVRequest(				IVRequest),
							.IVWrite(				IVWrite),
							.IVAddress(				IVAddress),
							.DataFromIV(			DataFromIV),
							.DataToIV(				DataToIV),

							.IVReady_BktOfI(		IVReady_BktOfI), 
							.IVDone_BktOfI(			IVDone_BktOfI));
							
		 if (EnableIV) begin:INTEGRITY
			IntegrityVerifier #(.DDR_nCK_PER_CLK(	DDR_nCK_PER_CLK),
							.DDRDQWidth(			DDRDQWidth),
							.DDRCWidth(				DDRCWidth),
							.DDRAWidth(				DDRAWidth),
							
							.ORAMB(					ORAMB),
							.ORAMU(					ORAMU),
							.ORAML(					ORAML),
							.ORAMZ(					ORAMZ),
							
							.IVEntropyWidth(		IVEntropyWidth))
					
				iv(			.Clock(					Clock),
							.Reset(					Reset || IVStart),
							
							.Request(				IVRequest),
							.Write(					IVWrite),
							.Address(				IVAddress),
							.DataIn(				DataToIV),
							.DataOut(				DataFromIV),
							
							.Done(					IVDone),
							.IVDone_BktOfI(			IVDone_BktOfI),
							
							.IVReady_BktOfI(		IVReady_BktOfI));
									
			// TODO: debugging now

			//assign	IVDone_BktOfI = 					1'b1;		
									
		end	else begin: NO_INTEGRITY		
			assign	IVRequest = 					1'b0;
			assign 	IVWrite = 						1'b0;
			assign 	IVAddress = 					0;
			assign	DataFromIV = 					0;
		
			// only the following two are important
			assign	IVDone = 						1'b1;
			assign	IVDone_BktOfI = 				1'b1;
		end
	end endgenerate
	
	//--------------------------------------------------------------------------
	//	Symmetric Encryption
	//--------------------------------------------------------------------------
	
	generate if (EnableAES) begin:AES
		if (EnableREW) begin:REW_AES
			AESREWORAM	#(	.ORAMZ(					ORAMZ),
							.ORAMU(					ORAMU),
							.ORAML(					ORAML),
							.ORAMB(					ORAMB),
							.ORAME(					ORAME),
							.DDR_nCK_PER_CLK(		DDR_nCK_PER_CLK),
							.DDRDQWidth(			DDRDQWidth),
							.IVEntropyWidth(		IVEntropyWidth),
							.AESWidth(				AESWidth),
							.Overclock(				Overclock),
							.EnableIV(				EnableIV))						
				aes(		.Clock(					Clock), 
							.FastClock(				FastClock),
				`ifdef ASIC
							.Reset(					Reset),
				`else
							.Reset(					1'b0), // this module doesn't need reset
				`endif
							.ROPAddr(				ROPAddr),
							.ROLeaf(				ROLeaf), 
							
							.BEDataOut(				AES_DRAMReadData), 
							.BEDataOutValid(		AES_DRAMReadDataValid), 					

							.BEDataIn(				AES_DRAMWriteData), 
							.BEDataInValid(			AES_DRAMWriteDataValid), 
							.BEDataInReady(			AES_DRAMWriteDataReady),	
							
							.DRAMReadData(			DRAMReadData), 
							.DRAMReadDataValid(		DRAMReadDataValid), 
							.DRAMReadDataReady(		DRAMReadDataReady),
							
							.DRAMWriteData(			DRAMWriteData), 
							.DRAMWriteDataValid(	DRAMWriteDataValid), 
							.DRAMWriteDataReady(	DRAMWriteDataReady));
		end else begin:BASIC_AES
			AESPathORAM #(	.ORAMB(					ORAMB), // TODO which of these params are really needed?
							.ORAMU(					ORAMU),
							.ORAML(					ORAML),
							.ORAMZ(					ORAMZ),
							.ORAMC(					ORAMC),
							.Overclock(				Overclock),
							.EnableREW(				EnableREW),
							.FEDWidth(				FEDWidth),
							.BEDWidth(				BEDWidth),
							.DDR_nCK_PER_CLK(		DDR_nCK_PER_CLK),
							.DDRDQWidth(			DDRDQWidth),
							.DDRCWidth(				DDRCWidth),
							.DDRAWidth(				DDRAWidth),
							.IVEntropyWidth(		IVEntropyWidth))
					aes(	.Clock(					Clock),
							.Reset(					Reset),

							.MIGOut(				DRAMWriteData),
							.MIGOutMask(			),
							.MIGOutValid(			DRAMWriteDataValid),
							.MIGOutReady(			DRAMWriteDataReady),

							.MIGIn(					DRAMReadData),
							.MIGInValid(			DRAMReadDataValid),
							.MIGInReady(			DRAMReadDataReady),
							
							.BackendRData(			AES_DRAMReadData),
							.BackendRValid(			AES_DRAMReadDataValid),
							.BackendRReady(			AES_DRAMReadDataReady),
							
							.BackendWData(			AES_DRAMWriteData),
							.BackendWMask(			AES_DRAMWriteMask),
							.BackendWValid(			AES_DRAMWriteDataValid),
							.BackendWReady(			AES_DRAMWriteDataReady),

							.DRAMInitDone(			DRAMInitComplete));
		end
	end else begin:NO_AES
		assign	DRAMWriteData = 					AES_DRAMWriteData;
		assign	DRAMWriteDataValid =				AES_DRAMWriteDataValid;
		assign	AES_DRAMWriteDataReady =			DRAMWriteDataReady;
	
		assign	AES_DRAMReadData =					DRAMReadData;
		assign	AES_DRAMReadDataValid =				DRAMReadDataValid;
		assign	DRAMReadDataReady = 				AES_DRAMReadDataReady;
	end endgenerate
	
	//--------------------------------------------------------------------------
endmodule
//------------------------------------------------------------------------------