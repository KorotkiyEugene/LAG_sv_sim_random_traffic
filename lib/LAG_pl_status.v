/* -------------------------------------------------------------------------------
 * (C)2007 Robert Mullins
 * Computer Architecture Group, Computer Laboratory
 * University of Cambridge, UK.
 * -------------------------------------------------------------------------------
 * 
 * Logic to determine if the virtual-channel held by a particular packet 
 * (buffered in an input PL FIFO) is blocked or ready?
 * 
 * Looks at currently allocated PL or the next free PL that would be allocated
 * at this port (as PL allocation may be taking place concurrently).
 * 
 */

module LAG_pl_status (output_port, 
		     allocated_pl,
		     allocated_pl_valid,
		     pl_status,
		     pl_blocked);

   parameter np=5;
   parameter nv=4;

   parameter unrestricted_pl_alloc = 0;
   
   input output_port_t output_port [np-1:0][nv-1:0]; 
   input [nv-1:0] allocated_pl [np-1:0][nv-1:0]; // allocated PL ID
   input [np-1:0][nv-1:0] allocated_pl_valid; // holding allocated PL?
   input [np-1:0][nv-1:0] pl_status; // blocked/ready status for each output PL
   output [np-1:0][nv-1:0] pl_blocked;
   
   logic [np-1:0][nv-1:0] b, current_pl_blocked;

   
   genvar ip,pl,op;
   
   generate
      for (ip=0; ip<np; ip++) begin:il
	 for (pl=0; pl<nv; pl++) begin:vl
	    	    
	    unary_select_pair #(ip, np, nv) blocked_mux
	      (output_port[ip][pl],
	       allocated_pl[ip][pl],
	       pl_status,
	       current_pl_blocked[ip][pl]);
	    
	    assign b[ip][pl] = current_pl_blocked[ip][pl];

	    assign pl_blocked[ip][pl] = (LAG_route_valid_input_pl (ip,pl)) ? b[ip][pl] : 1'b0;
	 end
      end 
      
   endgenerate
   
   
endmodule // LAG_pl_status
