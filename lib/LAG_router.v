/* -----------------------------------------------------------------------------
 * (C)2012 Korotkyi Ievgen
 * National Technical University of Ukraine "Kiev Polytechnic Institute"
 * -----------------------------------------------------------------------------
 */

module LAG_router (i_flit_in, i_flit_out,
		     i_cntrl_in, i_cntrl_out,
		     i_input_full_flag, 
		     clk, rst_n);

   `include "LAG_functions.v"
   
   parameter network_x = 4;
   parameter network_y = 4;
   
   parameter buf_len = 4;
   parameter NT=5;    // number of input-output trunks
   parameter NPL=4;   // number of pl in each trunk

   parameter alloc_stages = 1;

   // numbers of physical links on entry/exit to network?
   parameter router_num_pls_on_entry = 1;
   parameter router_num_pls_on_exit = 1;

//==================================================================

   // FIFO rec. data from tile/core is full?
   output  [router_num_pls_on_entry-1:0] i_input_full_flag;
   // link data and control
   input   flit_t i_flit_in [NT-1:0][NPL-1:0];
   output  flit_t i_flit_out [NT-1:0][NPL-1:0];
   input   chan_cntrl_t i_cntrl_in [NT-1:0];
   output  chan_cntrl_t i_cntrl_out [NT-1:0];
   input   clk, rst_n;
    
   logic [NT-1:0][NPL-1:0] x_pl_status;
   
   logic [NT-1:0][NPL-1:0] x_push;
   logic [NT-1:0][NPL-1:0] x_pop;
   
   flit_t x_flit_xbarin [NT-1:0][NPL-1:0];
   flit_t x_flit_xbarout [NT-1:0][NPL-1:0];
   
   flit_t x_flit_xbarin_ [NT*NPL-1:0];
   flit_t x_flit_xbarout_ [NT*NPL-1:0];
   
   flit_t routed [NT-1:0][NPL-1:0];
   
   logic [NT-1:0][NPL-1:0] flits_out_tail; 
   logic [NT-1:0][NPL-1:0] flits_out_valid;    //for any output channel of each output port

   fifov_flags_t x_flags [NT-1:0][NPL-1:0];
   logic [NPL-1:0] 	  x_allocated_pl [NT-1:0][NPL-1:0];
   logic [NT-1:0][NPL-1:0] x_allocated_pl_valid;   
   logic [NT-1:0][NPL-1:0][NPL-1:0] x_pl_new;
   logic [NT-1:0][NPL-1:0] 	  x_pl_new_valid;
   output_port_t x_output_port [NT-1:0][NPL-1:0];
   output_port_t x_output_port_reg [NT-1:0][NPL-1:0];
  
   logic [NT*NPL-1:0][NT*NPL-1:0] xbar_select; 
   logic [NT-1:0][NPL-1:0] pl_request;             // request for pl in out trunk from each input pl
   logic [NT-1:0][NPL-1:0] allocated_pl_blocked;  
 
   flit_t flit_buffer_out [NT-1:0][NPL-1:0];
   
   //
   // unrestricted PL free pool/allocation
   //
   logic [NT-1:0][NPL-1:0] pl_alloc_status;         // which output PLs are free to be allocated
   logic [NT-1:0][NPL-1:0] pl_allocated;            // indicates which PLs were allocated on this clock cycle
   logic [NT-1:0][NPL-1:0][NPL-1:0] pl_requested;    // which PLs were selected to be requested at each input PL?
   //
   logic [NT-1:0][NPL-1:0] 	  pl_empty;        // is downstream FIFO associated with PL empty?
   
   genvar 		  i,j,k,l;
   
   // *******************************************************************************
   // output ports
   // *******************************************************************************
   generate
   for (i=0; i<NT; i++) begin:output_ports1

      //
      // Flow Control 
      //
      LAG_pl_fc_out #(.num_pls(NPL),
		     .init_credits(buf_len))
	fcout (.flits_valid(flits_out_valid[i]),
	       .channel_cntrl_in(i_cntrl_in[i]),
	       .pl_status(x_pl_status[i]),
	       .pl_empty(pl_empty[i]), 
	       .clk, .rst_n);   
	       
      //      
      // Free PL pools 
      //
      
      if (i==`TILE) begin
	 //
	 // may have less than a full complement of PLs on exit from network
	 //
	 LAG_pl_free_pool #(.num_pls_local(router_num_pls_on_exit), 
			   .num_pls_global(NPL)
			   ) plfreepool
	   (.flits_tail(flits_out_tail[i]), 
	    .flits_valid(flits_out_valid[i]),
	    .pl_alloc_status(pl_alloc_status[i]),
	    .pl_allocated(pl_allocated[i]),
	    .pl_empty(pl_empty[i]),
	    .clk, .rst_n);
      end else begin
	 LAG_pl_free_pool #(.num_pls_local(NPL),
			   .num_pls_global(NPL)
			   ) plfreepool
	   (.flits_tail(flits_out_tail[i]), 
	    .flits_valid(flits_out_valid[i]),
	    .pl_alloc_status(pl_alloc_status[i]),
	    .pl_allocated(pl_allocated[i]),
	    .pl_empty(pl_empty[i]),
	    .clk, .rst_n);
      end // else: !if(i==`TILE)
      
      
      for (j=0; j<NPL; j++) begin:output_channels2
      
        assign flits_out_tail[i][j] = x_flit_xbarout[i][j].control.tail;
        assign flits_out_valid[i][j] = x_flit_xbarout[i][j].control.valid;
        
      end
      
      assign i_cntrl_out[i].credits = x_pop[i]; // if you want to register i_cntrl_out[i].credits, comment this line and uncomment lines below
     
      always@(posedge clk) begin
	 if (!rst_n) begin
	    //i_cntrl_out[i].credits <= '0;
	 end else begin
	    //
	    // ensure 'credit' is registered before it is sent to the upstream router
	    //

	    // send credit corresponding to flit sent from this input port
	    //i_cntrl_out[i].credits <= x_pop[i];    
	 end
      end
    
    end 
      
   endgenerate
   
      
   // *******************************************************************************
   // input trunks (pc buffers and PC registers)
   // *******************************************************************************

   generate
      for (i=0; i<router_num_pls_on_entry; i++) begin:plsx
	       assign i_input_full_flag[i] = x_flags[`TILE][i].full; // TILE input FIFO[i] is full?	       
      end

      
      for (i=0; i<NT; i++) begin:input_ports
	 
	 // input trunk 'i'
	 LAG_pl_input_trunk #(.num_pls(NPL), 
			    .buffer_length(buf_len)) inport
	   (.push(x_push[i]), 
	    .pop(x_pop[i]), 
	    .data_in(i_flit_in[i]), 
	    .data_out(flit_buffer_out[i]),
	    .flags(x_flags[i]), 
	    .allocated_pl(x_allocated_pl[i]), 
	    .allocated_pl_valid(x_allocated_pl_valid[i]), 
	    .pl_new(x_pl_new[i]), 
	    .pl_new_valid(x_pl_new_valid[i]),
	    .clk, .rst_n);
      

      for (j=0; j<NPL; j++) begin:allpls2

	      LAG_route rfn (.flit_in(flit_buffer_out[i][j]), .flit_out(routed[i][j]), .clk, .rst_n);
        
        assign x_push[i][j] = i_flit_in[i][j].control.valid;
	      assign x_output_port[i][j] = flit_buffer_out[i][j].control.head ? flit_buffer_out[i][j].data[NT-1:0] : x_output_port_reg[i][j];
	       
	    
      end
      
      for (j=0; j<NPL; j++) begin:allpls3
        always@(posedge clk) begin
	        if (!rst_n) begin
	          x_output_port_reg[i][j] <= '0;
	        end else if (flit_buffer_out[i][j].control.head) begin

	           x_output_port_reg[i][j] <= flit_buffer_out[i][j].data[NT-1:0];  
	         end
        end
      end

      for (j=0; j<NPL; j++) begin:reqs
	    //
	    // PHYSIC-CHANNEL ALLOCATION REQUESTS
	    //
        assign pl_request[i][j]= (LAG_route_valid_input_pl(i,j)) ? 
				  !x_flags[i][j].empty & !x_allocated_pl_valid[i][j] : 1'b0;
	 
	      assign x_pop[i][j] = !x_flags[i][j].empty & x_allocated_pl_valid[i][j] & ~allocated_pl_blocked[i][j];

      end // block: reqs
      
      
      for (j=0; j<NPL; j++) begin:flit_to_out_valid
        always_comb begin
          x_flit_xbarin[i][j] = flit_buffer_out[i][j].control.head ? routed[i][j] : flit_buffer_out[i][j];
        
          x_flit_xbarin[i][j].control.valid = x_pop[i][j];
        end
      end
      
   end // block: input_ports
      
   

   LAG_pl_status #(.np(NT), .nv(NPL)) vstat (.output_port(x_output_port), 
                                              .allocated_pl(x_allocated_pl),
                                              .allocated_pl_valid(x_allocated_pl_valid),
	                                            .pl_status(x_pl_status), 
                                              .pl_blocked(allocated_pl_blocked));
   
      
   endgenerate

   // ----------------------------------------------------------------------
   // physical-channel allocation logic
   // ----------------------------------------------------------------------
   LAG_pl_allocator #(.buf_len(buf_len), .np(NT), .nv(NPL), .xs(network_x), .ys(network_y), 
         .alloc_stages(alloc_stages)
		     )
     plalloc
       (.req(pl_request),
	.output_port(x_output_port),
	.pl_new(x_pl_new),
	.pl_new_valid(x_pl_new_valid),
	.pl_allocated(pl_allocated),
	.pl_alloc_status(pl_alloc_status), 
	.clk, .rst_n);

  generate
    for (i=0; i<NT; i++) begin: out_ports_xbar_select
      for (j=0; j<NPL; j++) begin: out_channels_xbar_select
        for (k=0; k<NT; k++) begin: in_ports_xbar_select
          for (l=0; l<NPL; l++) begin: in_channels_xbar_select
            assign xbar_select[i*NPL+j][k*NPL+l] = x_output_port_reg[k][l][i] & x_allocated_pl[k][l][j];
          end
        end
      end
    end  
  endgenerate
    
  generate
    for (i=0; i<NT; i++) begin: in_ports_xbar
      for (j=0; j<NPL; j++) begin: in_channels_xbar
        assign x_flit_xbarin_[i*NPL+j] = x_flit_xbarin[i][j];
      end
    end  
  endgenerate  
  
  generate
    for (i=0; i<NT; i++) begin: out_ports_xbar
      for (j=0; j<NPL; j++) begin: out_channels_xbar
        assign x_flit_xbarout[i][j] = x_flit_xbarout_[i*NPL+j];
      end
    end  
  endgenerate   
   
   // ----------------------------------------------------------------------
   // crossbar
   // ----------------------------------------------------------------------

	 LAG_crossbar_oh_select #(.n(NT*NPL)) myxbar 
	   (x_flit_xbarin_, xbar_select, x_flit_xbarout_); 
   
   
   // ----------------------------------------------------------------------
   // output port logic
   // ----------------------------------------------------------------------
   generate
   for (i=0; i<NT; i++) begin:outports
      for (j=0; j<NPL; j++) begin:outchannels
       
        assign i_flit_out[i][j] = x_flit_xbarout[i][j];
	
      end //block: outchannels
   end // block: outports
   
   endgenerate 
   
endmodule // simple_router
