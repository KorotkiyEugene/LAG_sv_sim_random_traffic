/* -------------------------------------------------------------------------------
 * (C)2007 Robert Mullins
 * Computer Architecture Group, Computer Laboratory
 * University of Cambridge, UK.
 * -------------------------------------------------------------------------------
 *
 *  *** NOT FOR SYNTHESIS ***
 * 
 * Random Packet Source for Open-Loop Measurement (see Dally/Towles p.450 and p.488)
 * 
 * - The injection time appended to packets is independent of activity in the network.
 *
 * - The random packet injection process is not paused while a packet is written to the
 *   input FIFO (which may take a number of cycles). If a new packet is generated 
 *   during this time it is copied to the FIFO as soon as possible.
 * 
 */

module LAG_random_traffic_source(flit_out, network_ready, clk, rst_n);

   parameter nv = 4; // number of virtual-channels available on entry to network
   
   parameter xdim = 4; // mesh network size
   parameter ydim = 4;
   parameter xpos = 0; // random source is connected to which router in mesh?
   parameter ypos = 0;
   parameter packet_length = 3;
   parameter rate = 0.1234; // flit injection rate (flits/cycle/random source)
   parameter router_radix = 5;

   localparam p = 10000*rate/packet_length;

   output flit_t flit_out;
   input [nv-1:0] network_ready;
   input clk, rst_n;

//==========
   
   integer sys_time, i_time, seed, inject_count, flit_count;
   
   logic   fifo_ready;
   
   logic   push, pop;
   flit_t data_in, data_out, routed, d;
   fifov_flags_t fifo_flags;
   integer xdest, ydest;

   integer injecting_packet;

   integer flits_buffered, flits_sent;

   integer length, len_sum, r;

   integer current_pl, blocked;

`ifndef DEBUG
   !!!! You must set the DEBUG switch if you are going to run a simulation !!!!
`endif
     
   //
   // FIFO connected to network input 
   //
   LAG_fifo_v #(.size(2+packet_length*4))
     source_fifo
       (.push(push),
	// dequeue if network was ready and fifo had a flit
	.pop(!fifo_flags.empty && network_ready[current_pl]),  
	.data_in(data_in), 
	.data_out(data_out),
	.flags(fifo_flags), .clk, .rst_n);
   
   LAG_route rfn (.flit_in(data_out), .flit_out(routed), .clk, .rst_n);
   
   always_comb
     begin
  if (data_out.control.head) begin  
	  flit_out = routed;
	end else begin
    flit_out = data_out;
  end  
	flit_out.control.valid = network_ready[current_pl] && !fifo_flags.empty;
     end

   //
   // Generate and Inject Packets at Random Intervals to Random Destinations
   //
   always@(posedge clk) begin
      if (!rst_n) begin

	 current_pl=0;
	 
	 flits_buffered=0;
	 flits_sent=0;
	 
	 injecting_packet=0;
	 sys_time=0;
	 i_time=0;
	 inject_count=0;
	 flit_count=0;

	 fifo_ready=1;

	 push=0;
	 
      end else begin

	 if (network_ready[current_pl]===1'bx) begin
	    $write ("Error: network_ready=%b", network_ready[current_pl]);
	    $finish;
	 end

	 if (!fifo_flags.empty && network_ready[current_pl]) flits_sent++;
	 if (push) flits_buffered++;
	 
	 //
	 // start buffering next flit when there is room in FIFO
	 //
	 if ((flits_buffered-flits_sent)<=packet_length) begin
	    fifo_ready = 1;
	 end

	 if (fifo_ready) begin
	    while ((i_time!=sys_time)&&(injecting_packet==0)) begin
	       
	       // **********************************************************
	       // Random Injection Process
	       // **********************************************************
	       // (1 and 10000 are possible random values)
	       if ($dist_uniform(seed, 1, 10000)<= p) begin
		  injecting_packet++;
	       end
	       
	       i_time++;

	    end // while (!injecting_packet && (i_time!=sys_time))
	 end

	 if (injecting_packet && !fifo_ready) begin
	    assert (flit_count==0) else $fatal;
	 end
	 
	 if (fifo_ready && injecting_packet) begin

	    // random source continues as we buffer flits in FIFO 
	    if ($dist_uniform(seed, 1, 10000)<=p) begin
	       injecting_packet++;
	    end
	    i_time++;
	    
	    flit_count++;
	    
	    push<=1'b1;

	    //
	    // Send Head Flit
	    //
	    if (flit_count!=1) begin
	     d.control.head = 1'b0;
	    
	    end else begin
	       d='0;
	       
	       inject_count++;
	       
	       //
	       // set random displacement to random destination
	       //
	       xdest = $dist_uniform (seed, 0, xdim-1);
	       ydest = $dist_uniform (seed, 0, ydim-1);
	       while ((xpos==xdest)&&(ypos==ydest)) begin
		  // don't send to self...
		  xdest = $dist_uniform (seed, 0, xdim-1);
		  ydest = $dist_uniform (seed, 0, ydim-1);
	       end

	       // simple traffic pattern
//	       xdest = xpos;
//	       ydest = 0;
	       //
	       
	       d.debug.xdest=xdest;
	       d.debug.ydest=ydest;
	       d.debug.xsrc=xpos;
	       d.debug.ysrc=ypos;
	       
	       d.data[router_radix + `X_ADDR_BITS : router_radix] = x_displ_t'(xdest-xpos);
	       d.data[router_radix + `X_ADDR_BITS + `Y_ADDR_BITS + 1 : router_radix + `X_ADDR_BITS + 1] = y_displ_t'(ydest-ypos);
	       d.control.head = 1'b1;

	       //
	       // Packets are injected on PLs selected in a round-robin fashion
	       // (If router_num_pls_on_entry==1, current_pl is always 0)
	       //
	       current_pl++; if (current_pl==nv) current_pl=0;
	       
//	       d.control.pl_id[0]=1'b1;

	       //
	       // select new PL that isn't blocked
	       //
	       // if all PLs are blocked, just selected PL round-robin
	       /*
	       if (!(|network_ready[current_pl])) begin
		  current_pl++; if (current_pl==nv) current_pl=0;
		  $display ("%m: All blocked");
	       end else begin
		  blocked=1;
		  while (blocked) begin
		     current_pl++; if (current_pl==nv) current_pl=0;
		     blocked=!network_ready[current_pl];
		  end
	       end
	       */
	       
	       /*
	       if (xdest>xpos) begin
		  current_pl=1;
	       end else begin
		  if (xdest<xpos) begin
		     current_pl=2;
		  end else begin
		     if (ydest>ypos) begin
			current_pl=3;
		     end else begin
			if (ydest<ypos) begin
			   current_pl=4;
			end
		     end
		  end // else: !if(xdest<xpos)
	       end // else: !if(xdest>xpos)
		*/
	       
	       //d.control.pl_id=1'b1 << current_pl;
	       	       
       
	       d.control.tail = 1'b0;
		     length = packet_length;
	       
	    end
 
	    
	    //
	    // add debug information to flit
	    //
	    d.debug.inject_time = i_time;
	    d.debug.flit_id = flit_count;
	    d.debug.packet_id = inject_count;
	    d.debug.hops = 0;

	    //
	    // Send Tail Flit
	    //
	    if (flit_count==length) begin
	       // inject tail
	       d.control.tail = 1'b1;
	       
	       injecting_packet--;	       
	       flit_count=0;

	       //
	       // wait for room in FIFO before generating next packet
	       //
//	       if ((flits_buffered-flits_sent)>=packet_length) begin
		  fifo_ready = 0;
//	       end
	    end
	    
	 end else begin // if (injecting_packet)
	    push<=1'b0;
	 end
	 
	 sys_time++;
	 
	 data_in<=d;
	 
      end // else: !if(!rst_n)
   end

   initial begin
      // we don't want any traffic sources to have the same 
      // random number seed!
      seed = xpos*50+ypos;
      len_sum=0;
      r= $dist_uniform(seed, 1, 10000);
      r= $dist_uniform(seed, 1, 10000);

   end
   
endmodule // LAG_random_source
