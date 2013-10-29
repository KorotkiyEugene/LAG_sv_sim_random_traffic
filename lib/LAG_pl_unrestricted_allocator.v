/* -------------------------------------------------------------------------------
 * Physical cgannel (PC) allocator 
 * Allocates new physical-channels in the destination trunk 
 * for newly arrived packets.
 * 
 * "unrestricted" allocation (Peh/Dally style)
 * 
 * Takes place in two stages:
 * 
 *           stage 1. ** Physical channel selection **
 *                    Each waiting packet determines which PC it will request.
 *                    (v:1 arbitration). 
 *                    
 * 
 *           stage 2. ** PC Allocation **
 *                    Access to each output PC is arbitrated (PV x PV:1 arbiters)
 * 
 */

module LAG_pl_unrestricted_allocator (req,              // PC request
				     output_port,      // for which trunk?
				     pl_status,        // which PCs are free
				     pl_new,           // newly allocated PC id.
				     pl_new_valid,     // has new PC been allocated?
				     pl_allocated,     // change PC status from free to allocated?
				     clk, rst_n);
   
   parameter buf_len = 4;
		
   parameter xs=4;
   parameter ys=4;
	
   parameter np=5;
   parameter nv=4;

   parameter plselect_arbstateupdate = 1;    // always/never update state of PL select matrix arbiter
   
   parameter alloc_stages = 1;
   
//-----   
   input [np-1:0][nv-1:0] req;
   input output_port_t output_port [np-1:0][nv-1:0];
   
   input [np-1:0][nv-1:0] pl_status;
   output [np-1:0][nv-1:0][nv-1:0] pl_new;
   output [np-1:0][nv-1:0] pl_new_valid;   
   output [np-1:0][nv-1:0] pl_allocated;  
   input clk, rst_n;

   genvar i,j,k,l;

   logic [np-1:0][nv-1:0][nv-1:0] stage1_request, stage1_grant, stage1_grant_reg;
   logic [np-1:0][nv-1:0][nv-1:0] selected_status;
   logic [np-1:0][nv-1:0][np-1:0][nv-1:0] stage2_requests, stage2_requests_, stage2_grants;
   logic [np-1:0][nv-1:0][nv-1:0][np-1:0] pl_new_;
   
   output_port_t output_port_reg [np-1:0][nv-1:0];
   
   generate
      for (i=0; i<np; i++) begin:foriports
	 for (j=0; j<nv; j++) begin:forpls
	    
	    if (alloc_stages == 2) begin
	    //	    
	    // Select PL status bits at output port of interest (determine which PLs are free to be allocated)
	    //
	    assign selected_status[i][j] = pl_status[oh2bin(output_port[i][j])];

	    //
	    // Requests for PL selection arbiter
	    //
	    // Narrows requests from all possible PLs that could be requested to 1
	    //
	    for (k=0; k<nv; k++) begin:forpls2
	       // Request is made if 
	       // (1) Packet requires PL
	       // (2) PL Mask bit is set
	       // (3) PL is currently free, so it can be allocated
	       //
	       assign stage1_request[i][j][k] = req[i][j] && selected_status[i][j][k] && ~(|stage1_grant_reg[i][j]);

	    end

      always @(posedge clk) begin
        if (!rst_n) begin
          stage1_grant_reg[i][j] <= '0; 
          output_port_reg[i][j] <= '0;
        end else begin
          stage1_grant_reg[i][j] <= stage1_grant[i][j];
          output_port_reg[i][j] <= output_port[i][j];
        end
      end 
	    
	    //
	    // second-stage of arbitration, determines who gets PL
	    //
	    for (k=0; k<np; k++) begin:fo
	       for (l=0; l<nv; l++) begin:fv
		  assign stage2_requests[k][l][i][j] = stage1_grant_reg[i][j][l] && output_port_reg[i][j][k];
		  assign stage2_requests_[k][l][i][j] = stage1_grant[i][j][l] && output_port[i][j][k];
	       end
	    end

	    assign pl_allocated[i][j] = |(stage2_requests_[i][j]);

      end else if (alloc_stages == 1) begin
      
         assign selected_status[i][j] = pl_status[oh2bin(output_port[i][j])];
         
         for (k=0; k<nv; k++) begin:forpls2

	         assign stage1_request[i][j][k] = req[i][j] && selected_status[i][j][k];

	       end
	       
	       for (k=0; k<np; k++) begin:fo
	         for (l=0; l<nv; l++) begin:fv
		          
		          assign stage2_requests[k][l][i][j] = stage1_grant[i][j][l] && output_port[i][j][k];
		          
	         end
	       end

	    assign pl_allocated[i][j] = |(stage2_requests[i][j]);
      
      end else begin
         //$display("Error: parameter <alloc_stages> can obtain only (1) or (2) values!");
         //$finish;
      end


      //
	    // first-stage of arbitration
	    //
	    // Arbiter state doesn't mean much here as requests on different clock cycles may be associated
	    // with different output ports. plselect_arbstateupdate determines if state is always or never
	    // updated.
	    //
	    //This stage determines one of free physical channel in te destination trunk
      //for each input physical channel that form request
      
	    matrix_arb #(.size(nv), .multistage(1))
			 stage1arb
			 (.request(stage1_request[i][j]),
			  .grant(stage1_grant[i][j]),
			  .success((plselect_arbstateupdate==1)), 
			  .clk, .rst_n);
			  
			//Second stage of arbitration. Eaxh output PC has one np*nv:1 arbiter 
      // 
	    // np*nv np*nv:1 tree arbiters
	    //
	    LAG_tree_arbiter #(.multistage(0),
                              .size(np*nv),
                              .groupsize(nv) ) plarb
              (.request(stage2_requests[i][j]),
               .grant(stage2_grants[i][j]),
               .clk, .rst_n);
               
               
	    for (k=0; k<np; k++) begin:fo2
	       for (l=0; l<nv; l++) begin:fv2
		  // could get pl x from any one of the output ports
		  assign pl_new_[i][j][l][k]=stage2_grants[k][l][i][j];
	       end
	    end
	    for (l=0; l<nv; l++) begin:fv3
	       assign pl_new[i][j][l]=|pl_new_[i][j][l];
	    end
	    assign pl_new_valid[i][j]=|pl_new[i][j];
	 end
      end
   endgenerate
   
endmodule // LAG_pl_unrestricted_allocator
