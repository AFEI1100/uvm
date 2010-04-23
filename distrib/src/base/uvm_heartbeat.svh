//----------------------------------------------------------------------
//   Copyright 2007-2009 Mentor Graphics Corp.
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
//----------------------------------------------------------------------

`ifndef UVM_HEARTBEAT_SVH
`define UVM_HEARTBEAT_SVH

typedef enum {
  UVM_ALL_ACTIVE,
  UVM_ONE_ACTIVE,
  UVM_ANY_ACTIVE,
  UVM_NO_HB_MODE
} uvm_heartbeat_modes;

//------------------------------------------------------------------------------
//
// Class: uvm_heartbeat
//
//------------------------------------------------------------------------------
// Heartbeats provide a way for environments to easily ensure that their
// descendants are alive. A uvm_heartbeat is associated with a specific
// objection object. A component that is being tracked by the heartbeat
// object must raise (or drop) an the synchronizing objection during
// the heartbeat window.
//
// The uvm_heartbeat object has a list of participating objects. The heartbeat
// can be configured so that all components (UVM_ALL_ACTIVE), exactly one
// (UVM_ONE_ACTIVE), or any component (UVM_ANY_ACTIVE) must trigger the
// objection in order to satisfy the heartbeat condition.
//------------------------------------------------------------------------------

typedef class uvm_hb_callback;
class uvm_heartbeat extends uvm_object;
  static protected uvm_objection_cbs_t m_global_cbs = uvm_objection_cbs_t::get_global_cbs();

  protected uvm_objection_cbs_t::queue_t m_cb_q;
  protected uvm_objection   m_objection = null;
  protected uvm_hb_callback m_cb = null;
  protected uvm_component   m_cntxt;
  protected uvm_heartbeat_modes   m_mode;
  protected uvm_component   m_hblist[$];
  protected uvm_event       m_event=null;
  protected bit             m_started=0;
  protected bit             m_stopped=0;

  // Function: new
  //
  // Creates a new heartbeat instance associated with ~cntxt~. The context
  // is the hierarchical locationa that the heartbeat objections will flow
  // through and be monitored at. The ~objection~ associated with the heartbeat 
  // is optional, if it is left null then the uvm_test_done objection is used. 
  //
  //| uvm_objection myobjection = new("myobjection"); //some shared objection
  //| class myenv extends uvm_env;
  //|    uvm_heartbeat hb = new("hb", this, myobjection);
  //|    ...
  //| endclass

  function new(string name, uvm_component cntxt, uvm_objection objection=null);
    super.new(name);
    m_objection = objection;
    
    //if a cntxt is given it will be used for reporting.
    if(cntxt != null) m_cntxt = cntxt;
    else m_cntxt = uvm_root::get();

    m_cb = new({name,"_cb"},m_cntxt);
    if(m_objection == null) m_objection = uvm_test_done_objection::get();

  endfunction


  // Function: hb_mode
  //
  // Sets or retrieves the heartbeat mode. The current value for the heartbeat
  // mode is returned. If an argument is specified to change the mode then the
  // mode is changed to the new value.

  function uvm_heartbeat_modes hb_mode (uvm_heartbeat_modes mode = UVM_NO_HB_MODE);
    hb_mode = m_mode;
    if(mode == UVM_ANY_ACTIVE || mode == UVM_ONE_ACTIVE || mode == UVM_ALL_ACTIVE)
      m_mode = mode;
  endfunction


  // Function: set_heartbeat 
  //
  // Sets up the heartbeat event and assigns a list of objects to watch. The
  // monitoring is started as soon as this method is called. Once the
  // monitoring has been started with a specific event, providing a new
  // monitor event results in an error. To change trigger events, you
  // must first <stop> the monitor and then <start> with a new event trigger.
  //
  // If the trigger event ~e~ is null and there was no previously set
  // trigger event, then the monitoring is not started. Monitoring can be 
  // started by explicitly calling <start>.

  function void set_heartbeat (uvm_event e, ref uvm_component comps[$]);
    uvm_object c;
    foreach(comps[i]) begin
      c = comps[i];
      if(!m_cb.cnt.exists(c)) 
        m_cb.cnt[c]=0;
      if(!m_cb.last_trigger.exists(c)) 
        m_cb.last_trigger[c]=0;
    end
    if(e==null && m_event==null) return;
    start(e);
  endfunction

  // Function: add
  //
  // Add a single component to the set of components to be monitored.
  // This does not cause monitoring to be started. If monitoring is
  // currently active then this component will be immediately added
  // to the list of components and will be expected to participate
  // in the currently active event window.

  function void add (uvm_component comp);
    uvm_object c = comp;
    if(m_cb.cnt.exists(c)) return;
    m_cb.cnt[c]=0;
    m_cb.last_trigger[c]=0;
  endfunction

  // Function: add
  //
  // Remove a single component to the set of components to be monitored.
  // Monitoring is not stopped, even if the last component has been
  // removed (an explicit stop is required).

  function void remove (uvm_component comp);
    uvm_object c = comp;
    if(m_cb.cnt.exists(c)) m_cb.cnt.delete(c);
    if(m_cb.last_trigger.exists(c)) m_cb.last_trigger.delete(c);
  endfunction


  // Function: start
  //
  // Starts the heartbeat monitor. If ~e~ is null then whatever event
  // was previously set is used. If no event was previously set then
  // a warning is issued. It is an error if the monitor is currently
  // running and ~e~ is specifying a different trigger event from the
  // current event.

  function void start (uvm_event e=null);
    if(m_event == null && e == null) begin
      m_cntxt.uvm_report_warning("NOEVNT", { "start() was called for: ",
        get_name(), " with a null trigger and no currently set trigger" },
        UVM_NONE);
      return;
    end
    if(m_event != null && e != m_event && m_started) begin
      m_cntxt.uvm_report_error("ILHBVNT", { "start() was called for: ",
        get_name(), " with trigger ", e.get_name(), " which is different ",
        "from the original trigger ", m_event.get_name() }, UVM_NONE);
      return;
    end  
    m_event = e;
    m_enable_cb();
    m_start_hb_process();
  endfunction

  // Function: stop
  //
  // Stops the heartbeat monitor. Current state information is reset so
  // that if <start> is called again the process will wait for the first
  // event trigger to start the monitoring.

  function void stop ();
    m_stopped = 1;
    m_disable_cb();
  endfunction

  function void m_start_hb_process();
    if(m_started) return;
    m_stopped = 0;
    fork
      m_hb_process;
    join_none
    m_started = 1;
  endfunction

  function void m_enable_cb;
    bit found = 0;
    m_cb.callback_mode(1);
    m_cb_q = m_global_cbs.get(m_objection);
    for(int i=0; i<m_cb_q.size(); ++i) begin
      if(m_cb_q.get(i) == m_cb) found = 1;
    end
    if(!found) 
      m_global_cbs.add_cb(m_objection, m_cb);
  endfunction

  function void m_disable_cb;
    m_cb.callback_mode(0);
  endfunction

  task m_hb_process;
    uvm_object obj;
    bit  triggered = 0;
    time last_trigger=0;
    fork
      begin
        while(1) begin
          m_event.wait_trigger();
          if(triggered) begin
            case (m_mode)
              UVM_ALL_ACTIVE:              
                begin
                  foreach(m_cb.cnt[idx]) begin
                    obj = idx;
                    if(!m_cb.cnt[obj]) begin
                      m_cntxt.uvm_report_fatal("HBFAIL", $sformatf("Did not recieve an update of %s for component %s since last event trigger at time %0t : last update time was %0t",
                        m_objection.get_name(), obj.get_full_name(), 
                        last_trigger, m_cb.last_trigger[obj]), UVM_NONE);
                    end
                  end
                end 
              UVM_ANY_ACTIVE:              
                begin
                  if(!m_cb.objects_triggered()) begin
                    string s;
                    foreach(m_cb.cnt[idx]) begin
                      obj = idx;
                      s={s,"\n",obj.get_full_name()};
                    end
                    m_cntxt.uvm_report_fatal("HBFAIL", $sformatf("Did not recieve an update of %s on any component since last event trigger at time %0t. The list of registered components is:%s",
                      m_objection.get_name(), last_trigger, s), UVM_NONE); 
                  end
                end 
              UVM_ONE_ACTIVE:              
                begin
                  if(m_cb.objects_triggered() != 1) begin
                    string s;
                    foreach(m_cb.cnt[idx])  begin
                      obj = idx;
                      if(m_cb.cnt[obj]) s={s,"\n",obj.get_full_name()};
                    end
                    m_cntxt.uvm_report_fatal("HBFAIL", $sformatf("Recieved update of %s from more than one component since last event trigger at time %0t. The list of triggered components is:%s",
                      m_objection.get_name(), last_trigger, s), UVM_NONE); 
                  end
                end 
            endcase
          end 
          m_cb.reset_counts();
          last_trigger = $time;
          triggered = 1;
        end
      end
      wait(m_stopped == 1);
    join_any
    disable fork;
    m_started = 0;
  endtask
endclass

class uvm_hb_callback extends uvm_objection_cb;
  int  cnt [uvm_object];
  time last_trigger [uvm_object];
  uvm_object target;

  function new(string name, uvm_object target);
    super.new(name);
    if(target != null) this.target = target;
    else this.target = uvm_root::get();
  endfunction

  virtual function void raised (uvm_object obj, uvm_object source_obj,
      string description, int count);
    if(obj == target) begin
      if(!cnt.exists(source_obj)) cnt[source_obj] = 0;
      cnt[source_obj] = cnt[source_obj]+1;
      last_trigger[source_obj] = $time;
    end
  endfunction
  virtual function void dropped (uvm_object obj, uvm_object source_obj,
      string description, int count);
    raised(obj,source_obj,description,count);
  endfunction

  function void reset_counts;
    foreach(cnt[i]) cnt[i] = 0;
  endfunction

  function int objects_triggered;
    objects_triggered = 0; 
    foreach(cnt[i]) if (cnt[i] != 0) objects_triggered++;
  endfunction
endclass

`endif

