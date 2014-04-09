`include "Const.vh"

module AddrGen
(Clock, Reset, Start, RWIn, BHIn, leaf, Ready, CmdReady, CmdValid, Cmd, Addr, currentLevel, STIdx, BktIdxInST, BktIdx);

	`include "PathORAM.vh";
	`include "DDR3SDRAM.vh";
  
	`include "DDR3SDRAMLocal.vh"
	`include "BucketDRAMLocal.vh"
	localparam ORAMLogL = `log2(ORAML);

	// =========================== in/out =========================
	input Clock; 

	// interface with backend ORAM controller
	input Reset, Start; 
	input RWIn;              // 0 for write, 1 for read, 
	input BHIn;              // 0 for the entire bucket, 1 for the header
	input [ORAML-1:0] leaf;
	output Ready;

	// interface with DRAM controller
	input CmdReady;
	output CmdValid;
	output [DDRCWidth-1:0] Cmd;
	output [DDRAWidth-1:0] Addr;

	// tmp output for debugging
	output [ORAMLogL-1:0]  currentLevel; 
	output [ORAML-1:0] STIdx, BktIdxInST;
	output [ORAML+1:0] BktIdx;
	// ====================================================
 
	// control logic for AddrGenBktHead
	wire Enable, SwitchLevel;
	reg RW, BH;
	reg [ORAMLogL-1:0] BktCounter;
     
	AddrGenBktHead #( .ORAML(ORAML), 
					.ORAMLogL(ORAMLogL),
					.DDRROWWidth(DDRROWWidth),
					.BktSize_DRWords(BktSize_DRWords)
					) 
	addGenBktHead (   Clock, Reset, Start && Ready, Enable, 
					leaf, 
					currentLevel, BktIdx,
					STIdx, BktIdxInST // tmp output for debugging
				  );  
			  
	assign SwitchLevel = BktCounter >= (BH ? BktHSize_DRBursts : BktSize_DRBursts) - 1;
	assign Enable = !Ready && CmdReady && SwitchLevel;

	// output 
	assign Ready = currentLevel > ORAML;
	assign CmdValid = currentLevel <= ORAML;
	assign Cmd = RW ? DDR3CMD_Read : DDR3CMD_Write;
	assign Addr = (BktIdx * BktSize_DRBursts + BktCounter) * DDRBstLen;

	always@(posedge Clock) begin
		if (Reset) begin
			RW <= 1'b0;
			BH <= 1'b0;
		end
		else if (Start && Ready) begin
			RW <= RWIn;
			BH <= BHIn;
			BktCounter <= 0;
		end

		if (!Ready && CmdReady) begin
			BktCounter <= SwitchLevel ? 0 : BktCounter + 1;
		end      
	end

endmodule
