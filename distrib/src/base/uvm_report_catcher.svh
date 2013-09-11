// $Id: uvm_report_catcher.svh,v 1.1.2.10 2010/04/09 15:03:25 janick Exp $
//------------------------------------------------------------------------------
//   Copyright 2007-2010 Mentor Graphics Corporation
//   Copyright 2007-2009 Cadence Design Systems, Inc.
//   Copyright 2010 Synopsys, Inc.
//   All Rights Reserved Worldwide
//
//   Licensed under the Apache License, Version 2.0 (the
//   "License"); you may not use this file except in
//   compliance with the License.  You may obtain a copy of
//   the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in
//   writing, software distributed under the License is
//   distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
//   CONDITIONS OF ANY KIND, either express or implied.  See
//   the License for the specific language governing
//   permissions and limitations under the License.
//------------------------------------------------------------------------------

`ifndef UVM_REPORT_CATCHER_SVH
`define UVM_REPORT_CATCHER_SVH

typedef class uvm_report_object;
typedef class uvm_report_handler;
typedef class uvm_report_server;
typedef class uvm_report_catcher;

typedef uvm_callbacks    #(uvm_report_object, uvm_report_catcher) uvm_report_cb;
typedef uvm_callback_iter#(uvm_report_object, uvm_report_catcher) uvm_report_cb_iter;

class sev_id_struct;
  bit sev_specified ;
  bit id_specified ;
  uvm_severity sev ;
  string  id ;
  bit is_on ;
endclass

//------------------------------------------------------------------------------
//
// CLASS: uvm_report_catcher
//
// The uvm_report_catcher is used to catch messages issued by the uvm report
// server. Catchers are
// uvm_callbacks#(<uvm_report_object>,uvm_report_catcher) objects,
// so all factilities in the <uvm_callback> and <uvm_callbacks#(T,CB)>
// classes are available for registering catchers and controlling catcher
// state.
// The uvm_callbacks#(<uvm_report_object>,uvm_report_catcher) class is
// aliased to ~uvm_report_cb~ to make it easier to use.
// Multiple report catchers can be 
// registered with a report object. The catchers can be registered as default 
// catchers which catch all reports on all <uvm_report_object> reporters,
// or catchers can be attached to specific report objects (i.e. components). 
//
// User extensions of <uvm_report_catcher> must implement the <catch> method in 
// which the action to be taken on catching the report is specified. The catch 
// method can return ~CAUGHT~, in which case further processing of the report is 
// immediately stopped, or return ~THROW~ in which case the (possibly modified) report 
// is passed on to other registered catchers. The catchers are processed in the order 
// in which they are registered.
//
// On catching a report, the <catch> method can modify the severity, id, action,
// verbosity or the report string itself before the report is finally issued by
// the report server. The report can be immediately issued from within the catcher 
// class by calling the <issue> method.
//
// The catcher maintains a count of all reports with FATAL,ERROR or WARNING severity
// and a count of all reports with FATAL, ERROR or WARNING severity whose severity
// was lowered. These statistics are reported in the summary of the <uvm_report_server>.
//
// This example shows the basic concept of creating a report catching
// callback and attaching it to all messages that get emitted:
//
//| class my_error_demoter extends uvm_report_catcher;
//|   function new(string name="my_error_demoter");
//|     super.new(name);
//|   endfunction
//|   //This example demotes "MY_ID" errors to an info message
//|   function action_e catch();
//|     if(get_severity() == UVM_ERROR && get_id() == "MY_ID")
//|       set_severity(UVM_INFO);
//|     return THROW;
//|   endfunction
//| endclass
//|
//| my_error_demoter demoter = new;
//| initial begin
//|  // Catchers are callbacks on report objects (components are report 
//|  // objects, so catchers can be attached to components).
//|
//|  // To affect all reporters, use null for the object
//|  uvm_report_cb::add(null, demoter); 
//|
//|  // To affect some specific object use the specific reporter
//|  uvm_report_cb::add(mytest.myenv.myagent.mydriver, demoter);
//|
//|  // To affect some set of components (any "*driver" under mytest.myenv)
//|  // using the component name
//|  uvm_report_cb::add_by_name("*driver", demoter, mytest.myenv);
//| end
//
//
//------------------------------------------------------------------------------

virtual class uvm_report_catcher extends uvm_callback;

  `uvm_register_cb(uvm_report_object,uvm_report_catcher)

  typedef enum { UNKNOWN_ACTION, THROW, CAUGHT} action_e;

  local static uvm_report_message m_modified_report_message;
  local static uvm_report_message m_orig_report_message;

  local static bit m_set_action_called;

  // Counts for the demoteds and caughts
  local static int m_demoted_fatal;
  local static int m_demoted_error;
  local static int m_demoted_warning;
  local static int m_caught_fatal;
  local static int m_caught_error;
  local static int m_caught_warning;

  // Flag counts
  const static int DO_NOT_CATCH      = 1; 
  const static int DO_NOT_MODIFY     = 2; 
  local static int m_debug_flags;

  local static  bit do_report;

  // Local report message for the uvm_report_* methods herein.
  uvm_report_message l_rm;
  
  // Function: new
  //
  // Create a new report catcher. The name argument is optional, but
  // should generally be provided to aid in debugging.

  function new(string name = "uvm_report_catcher");
    super.new(name);
    l_rm = new("uvm_report_message");
    do_report = 1;
  endfunction    

  // Group: Current Message State

  // Function: get_client
  //
  // Returns the <uvm_report_object> that has generated the message that
  // is currently being processes.  This field is not modifiable.

  function uvm_report_object get_client();
    return m_modified_report_message.report_object; 
  endfunction

  // Function: get_severity
  //
  // Returns the <uvm_severity> of the message that is currently being
  // processed. If the severity was modified by a previously executed
  // catcher object (which re-threw the message), then the returned 
  // severity is the modified value.

  function uvm_severity get_severity();
    return this.m_modified_report_message.severity;
  endfunction
  
  // Function: get_context
  //
  // Returns the context (source) of the message that is currently being
  // processed. This is typically the full hierarchical name of the component
  // that issued the message. However, when the message comes via a report
  // handler that is not associated with a component, the context is
  // user-defined.

  function string get_context();
    string context_str;
    
    context_str = this.m_modified_report_message.context_name;
    if (context_str == "")
      context_str = this.m_modified_report_message.report_handler.get_full_name();

    return context_str;
  endfunction
  
  // Function: get_verbosity
  //
  // Returns the verbosity of the message that is currently being
  // processed. If the verbosity was modified by a previously executed
  // catcher (which re-threw the message), then the returned 
  // verbosity is the modified value.
  
  function int get_verbosity();
    return this.m_modified_report_message.verbosity;
  endfunction
  
  // Function: get_id
  //
  // Returns the string id of the message that is currently being
  // processed. If the id was modified by a previously executed
  // catcher (which re-threw the message), then the returned 
  // id is the modified value.
  
  function string get_id();
    return this.m_modified_report_message.id;
  endfunction
  
  // Function: get_message
  //
  // Returns the string message of the message that is currently being
  // processed. If the message was modified by a previously executed
  // catcher (which re-threw the message), then the returned 
  // message is the modified value.
  
  function string get_message();
     return this.m_modified_report_message.message;
  endfunction
  
  // Function: get_action
  //
  // Returns the <uvm_action> of the message that is currently being
  // processed. If the action was modified by a previously executed
  // catcher (which re-threw the message), then the returned 
  // action is the modified value.
  
  function uvm_action get_action();
    return this.m_modified_report_message.action;
  endfunction
  
  // Function: get_fname
  //
  // Returns the file name of the message.
  
  function string get_fname();
    return this.m_modified_report_message.filename;
  endfunction             

  // Function: get_line
  //
  // Returns the line number of the message.

  function int get_line();
    return this.m_modified_report_message.line;
  endfunction

  
  // Group: Change Message State

  // Function: set_severity
  //
  // Change the severity of the message to ~severity~. Any other
  // report catchers will see the modified value.
  
  protected function void set_severity(uvm_severity severity);
    this.m_modified_report_message.severity = uvm_severity_type'(severity);
  endfunction
  
  // Function: set_verbosity
  //
  // Change the verbosity of the message to ~verbosity~. Any other
  // report catchers will see the modified value.

  protected function void set_verbosity(int verbosity);
    this.m_modified_report_message.verbosity = verbosity;
  endfunction      

  // Function: set_id
  //
  // Change the id of the message to ~id~. Any other
  // report catchers will see the modified value.

  protected function void set_id(string id);
    this.m_modified_report_message.id = id;
  endfunction
  
  // Function: set_message
  //
  // Change the text of the message to ~message~. Any other
  // report catchers will see the modified value.

  protected function void set_message(string message);
    this.m_modified_report_message.message = message;
  endfunction
  
  // Function: set_action
  //
  // Change the action of the message to ~action~. Any other
  // report catchers will see the modified value.
  
  protected function void set_action(uvm_action action);
    this.m_modified_report_message.action = action;
    this.m_set_action_called = 1;
  endfunction

  // Function: set_context
  //
  // Change the context of the message to ~context~. Any other
  // report catchers will see the modified value.

  protected function void set_context(string context);
    this.m_modified_report_message.context_name = context;
  endfunction

  // Function: add_int
  //
  // Add an integral type of the name ~name~ and value ~value~ to
  // the message.  The required ~size~ field indicates the size of ~value~.
  // The required ~radix~ field determines how to display and
  // record the field. Any other report catchers will see the newly
  // added element.
  //

  protected function void add_int(string name, uvm_bitstream_t value,
                        int size, uvm_radix_enum radix, bit print = 1, bit record = 1);
    this.m_modified_report_message.add_int(name, value, size, radix, print, record);
  endfunction


  // Function: add_string
  //
  // Adds a string of the name ~name~ and value ~value~ to the
  // message. Any other report catchers will see the newly
  // added element.
  //

  protected function void add_string(string name, string value, bit print = 1, bit record = 1);
    this.m_modified_report_message.add_string(name, value, print, record);
  endfunction


  // Function: add_object
  //
  // Adds a uvm_object of the name ~name~ and reference ~obj~ to
  // the message. Any other report catchers will see the newly
  // added element.
  //

  protected function void add_object(string name, uvm_object obj, bit print = 1, bit record = 1);
    this.m_modified_report_message.add_object(name, obj, print, record);
  endfunction

  
  // Group: Debug
     
  // Function: get_report_catcher
  //
  // Returns the first report catcher that has ~name~. 
  
  static function uvm_report_catcher get_report_catcher(string name);
    static uvm_report_cb_iter iter = new(null);
    get_report_catcher = iter.first();
    while(get_report_catcher != null) begin
      if(get_report_catcher.get_name() == name)
        return get_report_catcher;
      get_report_catcher = iter.next();
    end
    return null;
  endfunction


  // Function: print_catcher
  //
  // Prints information about all of the report catchers that are 
  // registered. For finer grained detail, the <uvm_callbacks #(T,CB)::display>
  // method can be used by calling uvm_report_cb::display(<uvm_report_object>).

  static function void print_catcher(UVM_FILE file=0);
	  string msg;
	  string enabled;
	  uvm_report_catcher catcher;
	  static uvm_report_cb_iter iter = new(null);
	  string q[$];

	  q.push_back("-------------UVM REPORT CATCHERS----------------------------\n");

	  catcher = iter.first();
	  while(catcher != null) begin
		  if(catcher.callback_mode())
			  enabled = "ON";        
		  else
			  enabled = "OFF";        

		  q.push_back($sformatf("%20s : %s\n", catcher.get_name(),enabled));
		  catcher = iter.next();
	  end
	  q.push_back("--------------------------------------------------------------\n");
	  begin
		  string msg;
		  msg={>>{q}};
		  `uvm_info_context("UVM/REPORT/CATCHER",msg,UVM_LOW,uvm_top)
	  end

  endfunction
  
  // Funciton: debug_report_catcher
  //
  // Turn on report catching debug information. ~what~ is a bitwise and of
  // * DO_NOT_CATCH  -- forces catch to be ignored so that all catchers see the
  //   the reports.
  // * DO_NOT_MODIFY -- forces the message to remain unchanged

  static function void debug_report_catcher(int what= 0);
    m_debug_flags = what;
  endfunction        
  
  // Group: Callback Interface
 
  // Function: catch
  //
  // This is the method that is called for each registered report catcher.
  // There are no arguments to this function. The <Current Message State>
  // interface methods can be used to access information about the 
  // current message being processed.

  pure virtual function action_e catch();
     

  // Group: Reporting

   // Function: uvm_report_fatal
   //
   // Issues a fatal message using the current message's report object.
   // This message will bypass any message catching callbacks.
   
   protected function void uvm_report_fatal(string id, string message, 
     int verbosity, string fname = "", int line = 0,
     string context_name = "", bit report_enabled_checked = 0);

     this.uvm_report(UVM_FATAL, id, message, UVM_NONE, fname, line,
                     context_name, report_enabled_checked);
   endfunction  


   // Function: uvm_report_error
   //
   // Issues a error message using the current message's report object.
   // This message will bypass any message catching callbacks.
   
   protected function void uvm_report_error(string id, string message, 
     int verbosity, string fname = "", int line = 0,
     string context_name = "", bit report_enabled_checked = 0);

     this.uvm_report(UVM_ERROR, id, message, UVM_NONE, fname, line,
                     context_name, report_enabled_checked);
   endfunction  
     

   // Function: uvm_report_warning
   //
   // Issues a warning message using the current message's report object.
   // This message will bypass any message catching callbacks.
   
   protected function void uvm_report_warning(string id, string message,
     int verbosity, string fname = "", int line = 0, 
     string context_name = "", bit report_enabled_checked = 0);

     this.uvm_report(UVM_WARNING, id, message, UVM_NONE, fname, line,
                     context_name, report_enabled_checked);
   endfunction  


   // Function: uvm_report_info
   //
   // Issues a info message using the current message's report object.
   // This message will bypass any message catching callbacks.
   
   protected function void uvm_report_info(string id, string message, 
     int verbosity, string fname = "", int line = 0,
     string context_name = "", bit report_enabled_checked = 0);

     this.uvm_report(UVM_INFO, id, message, verbosity, fname, line,
                     context_name, report_enabled_checked);
   endfunction  

   // Function: uvm_report
   //
   // Issues a message using the current message's report object.
   // This message will bypass any message catching callbacks.

   protected function void uvm_report(uvm_severity severity, string id, string message,
     int verbosity, string fname = "", int line = 0,
     string context_name = "", bit report_enabled_checked = 0);
     uvm_action a;
     if (report_enabled_checked == 0) begin
       if (!uvm_report_enabled(verbosity, severity, id))
         return;
     end

     a = m_modified_report_message.report_object.get_report_action(severity, id);
     if(a) begin
       l_rm.report_object = m_modified_report_message.report_object;
       l_rm.report_handler = m_modified_report_message.report_handler;
       l_rm.report_server = m_modified_report_message.report_server;
       l_rm.context_name = context_name;
       l_rm.file = l_rm.report_object.get_report_file_handle(severity, id);
       l_rm.filename = fname;
       l_rm.line = line;
       l_rm.action = a;
       l_rm.severity = uvm_severity_type'(severity);
       l_rm.id = id;
       l_rm.message = message;
       l_rm.verbosity = verbosity;
       l_rm.tr_handle = -1;
       l_rm.report_server.execute_report_message(l_rm);
     end
   endfunction


  // Function: issue
  // Immediately issues the message which is currently being processed. This
  // is useful if the message is being ~CAUGHT~ but should still be emitted.
  //
  // Issuing a message will update the report_server stats, possibly multiple 
  // times if the message is not ~CAUGHT~.

  protected function void issue();
     m_modified_report_message.report_server.execute_report_message(m_modified_report_message);
  endfunction


  //process_all_report_catchers
  //method called by report_server.report to process catchers
  //

  static function int process_all_report_catchers(uvm_report_message rm);
    int iter;
    uvm_report_catcher catcher;
    int thrown = 1;
    uvm_severity orig_severity;
    static bit in_catcher;

    if(in_catcher == 1) begin
        return 1;
    end
    in_catcher = 1;    
    uvm_callbacks_base::m_tracing = 0;  //turn off cb tracing so catcher stuff doesn't print

    orig_severity = uvm_severity'(rm.severity);
    m_modified_report_message = rm;

    catcher = uvm_report_cb::get_first(iter,rm.report_object);
    if (catcher != null) begin
      if(m_debug_flags & DO_NOT_MODIFY) begin
        process p = process::self(); // Keep random stability
        string randstate = p.get_randstate();
        $cast(m_orig_report_message, rm.clone()); //have to clone, rm can be extended type
        p.set_randstate(randstate);
      end
    end
    while(catcher != null) begin
      uvm_severity prev_sev;

      if (!catcher.callback_mode()) begin
        catcher = uvm_report_cb::get_next(iter,rm.report_object);
        continue;
      end

      prev_sev = m_modified_report_message.severity;
      m_set_action_called = 0;
      thrown = catcher.process_report_catcher();

      // Set the action to the default action for the new severity
      // if it is still at the default for the previous severity,
      // unless it was explicitly set.
      if (!m_set_action_called && 
          m_modified_report_message.severity != prev_sev && 
          m_modified_report_message.action == 
            rm.report_object.get_report_action(prev_sev, "*@&*^*^*#")) begin
         m_modified_report_message.action =
           rm.report_object.get_report_action(m_modified_report_message.severity, "*@&*^*^*#");
      end

      if(thrown == 0) begin 
        case(orig_severity)
          UVM_FATAL:   m_caught_fatal++;
          UVM_ERROR:   m_caught_error++;
          UVM_WARNING: m_caught_warning++;
         endcase   
         break;
      end 
      catcher = uvm_report_cb::get_next(iter,rm.report_object);
    end //while

    //update counters if message was returned with demoted severity
    case(orig_severity)
      UVM_FATAL:    
        if(m_modified_report_message.severity < orig_severity)
          m_demoted_fatal++;
      UVM_ERROR:
        if(m_modified_report_message.severity < orig_severity)
          m_demoted_error++;
      UVM_WARNING:
        if(m_modified_report_message.severity < orig_severity)
          m_demoted_warning++;
    endcase

    in_catcher = 0;
    uvm_callbacks_base::m_tracing = 1;  //turn tracing stuff back on

    return thrown; 
  endfunction


  //process_report_catcher
  //internal method to call user catch() method
  //

  local function int process_report_catcher();

    action_e act;

    act = this.catch();

    if(act == UNKNOWN_ACTION)
      this.uvm_report_error("RPTCTHR", {"uvm_report_this.catch() in catcher instance ",
        this.get_name(), " must return THROW or CAUGHT"}, UVM_NONE, `uvm_file, `uvm_line);

    if(m_debug_flags & DO_NOT_MODIFY) begin
      m_modified_report_message.copy(m_orig_report_message);
    end     

    if(act == CAUGHT  && !(m_debug_flags & DO_NOT_CATCH)) begin
      return 0;
    end  

    return 1;

  endfunction


  // Function: summarize
  //
  // This function is called automatically by <uvm_report_server::summarize()>.
  // It prints the statistics for the active catchers.


  static function void summarize();
    string s;
    string q[$];
    if(do_report) begin
      q.push_back("\n");   
      q.push_back("--- UVM Report catcher Summary ---");
      q.push_back("");   
      q.push_back("");
  
      q.push_back($sformatf("Number of demoted UVM_FATAL reports  :%5d\n", m_demoted_fatal));
      q.push_back($sformatf("Number of demoted UVM_ERROR reports  :%5d\n", m_demoted_error));
      q.push_back($sformatf("Number of demoted UVM_WARNING reports:%5d\n", m_demoted_warning));
      q.push_back($sformatf("Number of caught UVM_FATAL reports   :%5d\n", m_caught_fatal));
      q.push_back($sformatf("Number of caught UVM_ERROR reports   :%5d\n", m_caught_error));
      q.push_back($sformatf("Number of caught UVM_WARNING reports :%5d\n", m_caught_warning));

		begin
			string msg;
			msg={>>{q}};
			`uvm_info_context("UVM/REPORT/CATCHER",msg,UVM_LOW,uvm_top)
		end
    end
  endfunction

endclass

`endif // UVM_REPORT_CATCHER_SVH
