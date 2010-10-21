// 
// -------------------------------------------------------------
//    Copyright 2004-2008 Synopsys, Inc.
//    Copyright 2010 Mentor Graphics Corp.
//    All Rights Reserved Worldwide
// 
//    Licensed under the Apache License, Version 2.0 (the
//    "License"); you may not use this file except in
//    compliance with the License.  You may obtain a copy of
//    the License at
// 
//        http://www.apache.org/licenses/LICENSE-2.0
// 
//    Unless required by applicable law or agreed to in
//    writing, software distributed under the License is
//    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
//    CONDITIONS OF ANY KIND, either express or implied.  See
//    the License for the specific language governing
//    permissions and limitations under the License.
// -------------------------------------------------------------
//

//
// TITLE: Register Access Test Sequence
//

typedef class uvm_mem_access_seq;

//
// class: uvm_reg_single_access_seq
//
// Verify the accessibility of a register
// by writing through its default address map
// then reading it via the backdoor, then reversing the process,
// making sure that the resulting value matches the mirrored value.
//
// Registers without an available backdoor or
// that contain read-only fields only,
// or fields with unknown access policies
// cannot be tested.
//
// The DUT should be idle and not modify any register during this test.
//

class uvm_reg_single_access_seq extends uvm_reg_sequence;

   // Variable: rg
   // The register to be tested
   uvm_reg rg;

   `uvm_object_utils(uvm_reg_single_access_seq)

   function new(string name="uvm_reg_single_access_seq");
     super.new(name);
   endfunction

   virtual task body();
      uvm_reg_mem_map maps[$];

      if (rg == null) begin
         `uvm_error("RegMem", "No register specified to run sequence on");
         return;
      end

      // Can only deal with registers with backdoor access
      if (rg.get_backdoor() == null && !rg.has_hdl_path()) begin
         `uvm_error("RegMem", $psprintf("Register \"%s\" does not have a backdoor mechanism available",
                                       rg.get_full_name()));
         return;
      end

      // Registers may be accessible from multiple physical interfaces (maps)
      rg.get_maps(maps);

      // Cannot test access if register contains RO or OTHER fields
      begin
         uvm_reg_field fields[$];

         rg.get_fields(fields);
         foreach (fields[j]) begin
            foreach (maps[k]) begin
               if (fields[j].get_access(maps[k]) == "RO") begin
                  `uvm_warning("RegMem", $psprintf("Register \"%s\" has RO fields",
                                                rg.get_full_name()));
                  return;
               end
               if (!fields[j].is_known_access(maps[k])) begin
                  `uvm_warning("RegMem", $psprintf("Register \"%s\" has fields with unknown access type \"%s\"",
                                                rg.get_full_name(),
                                                fields[j].get_access(maps[k])));
                  return;
               end
            end
         end
      end
      
      // Access each register:
      // - Write complement of reset value via front door
      // - Read value via backdoor and compare against mirror
      // - Write reset value via backdoor
      // - Read via front door and compare against mirror
      foreach (maps[j]) begin
         uvm_status_e status;
         uvm_reg_mem_data_t  v, exp;
         
         `uvm_info("RegMem", $psprintf("Verifying access of register %s in map \"%s\"...",
                                    rg.get_full_name(), maps[j].get_full_name()), UVM_LOW);
         
         v = rg.get();
         
         rg.write(status, ~v, UVM_BFM, maps[j], this);
         if (status != UVM_IS_OK) begin
            `uvm_error("RegMem", $psprintf("Status was %s when writing \"%s\" through map \"%s\".",
                                        status.name(), rg.get_full_name(), maps[j].get_full_name()));
         end
         #1;
         
         rg.mirror(status, UVM_CHECK, UVM_BACKDOOR, uvm_reg_mem_map::backdoor(), this);
         if (status != UVM_IS_OK) begin
            `uvm_error("RegMem", $psprintf("Status was %s when reading reset value of register \"%s\" through backdoor.",
                                        status.name(), rg.get_full_name()));
         end
         
         rg.write(status, v, UVM_BACKDOOR, maps[j], this);
         if (status != UVM_IS_OK) begin
            `uvm_error("RegMem", $psprintf("Status was %s when writing \"%s\" through backdoor.",
                                        status.name(), rg.get_full_name()));
         end
         
         rg.mirror(status, UVM_CHECK, UVM_BFM, maps[j], this);
         if (status != UVM_IS_OK) begin
            `uvm_error("RegMem", $psprintf("Status was %s when reading reset value of register \"%s\" through map \"%s\".",
                                        status.name(), rg.get_full_name(), maps[j].get_full_name()));
         end
      end
   endtask: body
endclass: uvm_reg_single_access_seq


//
// class: uvm_reg_access_seq
//
// Verify the accessibility of all registers in a block
// by executing the <uvm_reg_single_access_seq> sequence on
// every register within it.
//
// Blocks and registers with the NO_REG_TESTS or
// the NO_REG_ACCESS_TEST attribute are not verified.
//

class uvm_reg_access_seq extends uvm_reg_sequence;

   `uvm_object_utils(uvm_reg_access_seq)

   function new(string name="uvm_reg_access_seq");
     super.new(name);
   endfunction

   // variable: regmem
   // The block to be tested
   
   virtual task body();

      if (regmem == null) begin
         `uvm_error("RegMem", "Not block or system specified to run sequence on");
         return;
      end

      uvm_report_info("STARTING_SEQ",{"\n\nStarting ",get_name()," sequence...\n"},UVM_LOW);
      
      if (regmem.get_attribute("NO_REG_TESTS") == "") begin
        if (regmem.get_attribute("NO_REG_ACCESS_TEST") == "") begin
           uvm_reg regs[$];
           uvm_reg_single_access_seq sub_seq;

           sub_seq = uvm_reg_single_access_seq::type_id::create("single_reg_access_seq");
           this.reset_blk(regmem);
           regmem.reset();

           // Iterate over all registers, checking accesses
           regmem.get_registers(regs);
           foreach (regs[i]) begin
              // Registers with some attributes are not to be tested
              if (regs[i].get_attribute("NO_REG_TESTS") != "" ||
	          regs[i].get_attribute("NO_REG_ACCESS_TEST") != "") continue;

              // Can only deal with registers with backdoor access
              if (regs[i].get_backdoor() == null && !regs[i].has_hdl_path()) begin
                 `uvm_warning("RegMem", $psprintf("Register \"%s\" does not have a backdoor mechanism available",
                                               regs[i].get_full_name()));
                 continue;
              end

              sub_seq.rg = regs[i];
              sub_seq.start(null,this);
           end
        end
      end

   endtask: body


   //
   // task: reset_blk
   // Reset the DUT that corresponds to the specified block abstraction class.
   //
   // Currently empty.
   // Will rollback the environment's phase to the ~reset~
   // phase once the new phasing is available.
   //
   // In the meantime, the DUT should be reset before executing this
   // test sequence or this method should be implemented
   // in an extension to reset the DUT.
   //
   virtual task reset_blk(uvm_reg_mem_block blk);
   endtask

endclass: uvm_reg_access_seq



//
// class: uvm_reg_mem_access_seq
//
// Verify the accessibility of all registers and memories in a block
// by executing the <uvm_reg_access_seq> and
// <uvm_mem_access_seq> sequence respectively on every register
// and memory within it.
//
// Blocks and registers with the NO_REG_TESTS or
// the NO_REG_ACCESS_TEST attribute are not verified.
//

class uvm_reg_mem_access_seq extends uvm_reg_sequence;

   `uvm_object_utils(uvm_reg_mem_access_seq)

   function new(string name="uvm_reg_mem_access_seq");
     super.new(name);
   endfunction

   virtual task body();

      if (regmem == null) begin
         `uvm_error("RegMem", "Not block or system specified to run sequence on");
         return;
      end

      uvm_report_info("STARTING_SEQ",{"\n\nStarting ",get_name()," sequence...\n"},UVM_LOW);
      
      if (regmem.get_attribute("NO_REG_TESTS") == "") begin
        if (regmem.get_attribute("NO_REG_ACCESS_TEST") == "") begin
           uvm_reg_access_seq sub_seq = new("reg_access_seq");
           this.reset_blk(regmem);
           regmem.reset();
           sub_seq.regmem = regmem;
           sub_seq.start(null,this);
        end
        if (regmem.get_attribute("NO_MEM_ACCESS_TEST") == "") begin
           uvm_mem_access_seq sub_seq = new("mem_access_seq");
           this.reset_blk(regmem);
           regmem.reset();
           sub_seq.regmem = regmem;
           sub_seq.start(null,this);
        end
      end

   endtask: body


   // Any additional steps required to reset the block
   // and make it accessibl
   virtual task reset_blk(uvm_reg_mem_block blk);
   endtask


endclass: uvm_reg_mem_access_seq


