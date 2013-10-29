/* -------------------------------------------------------------------------------
 * (C)2007 Robert Mullins
 * Computer Architecture Group, Computer Laboratory
 * University of Cambridge, UK.
 * -------------------------------------------------------------------------------
 * 
 * PL allocator 
 * 
 * Allocates new virtual-channels for newly arrived packets.
 * 
 * Supported PL allocation architectures:
 * 
 *    (A) "fifo_free_pool" - Free PL pool is organised as a FIFO, at most one PL
 *        may be allocated per output port per clock cycle
 * 
 *           In this case we just need P x PV:1 arbiters
 * 
 *    (B) "unrestricted"   - Peh/Dally style PL allocation. 
 *        Takes place in two stages:
 * 
 *           stage 1. Each waiting packet determines which PL it will request.
 *                    (v:1 arbitration). Can support PL alloc. mask here (from 
 *                    packet header or static or dynamic..)
 *                    
 * 
 *           stage 2. Access to each output PL is arbitrated (PV x PV:1 arbiters)
 * 
 */

module LAG_pl_allocator (req, output_port,      // PL request, for which port?
			pl_new, pl_new_valid,  // newly allocated PL ids
			pl_allocated,          // which PLs were allocated on this cycle?
			pl_alloc_status,       // which PLs are free?
			clk, rst_n);
   
   parameter buf_len=4;
   
   parameter xs=4;
   parameter ys=4;
		
   parameter np=5;
   parameter nv=4;

   parameter alloc_stages = 1;  
   
//-----
   input [np-1:0][nv-1:0] req;
   input output_port_t output_port [np-1:0][nv-1:0];
   output [np-1:0][nv-1:0][nv-1:0] pl_new;
   output [np-1:0][nv-1:0] pl_new_valid;
   output [np-1:0][nv-1:0] pl_allocated;  
   input [np-1:0][nv-1:0] pl_alloc_status;
   
   input clk, rst_n;

   generate
	 
	 LAG_pl_unrestricted_allocator
	   #(.np(np), .nv(nv), .xs(xs), .ys(ys), .buf_len(buf_len), 
       .alloc_stages(alloc_stages)
       ) unrestricted
	       (
		.req, 
		.output_port,                 
		.pl_status(pl_alloc_status),        
		.pl_new,          
		.pl_new_valid,    
		.pl_allocated,   
		.clk, .rst_n
		);

   endgenerate

endmodule // LAG_pl_allocator

