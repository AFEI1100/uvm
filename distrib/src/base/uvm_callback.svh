//----------------------------------------------------------------------
//   Copyright 2007-2010 Mentor Graphics, Corp.
//   Copyright 2007-2010 Cadence Design Systems, Inc.
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

`include "uvm_macros.svh"

`ifndef UVM_CALLBACK_SVH
`define UVM_CALLBACK_SVH

typedef class uvm_callback;
//typedef class uvm_callbacks;
typedef class uvm_callbacks_base;

// Class - uvm_typeid_base
// Class - uvm_typeid#(T)
//
// Simple typeid interface. Need this to set up the base-super mapping.
// This is similar to the factory, but much simpler. The idea of this
// interface is that each object type T has a typeid that can be
// used for mapping type relationships. This is not a user visible class.
class uvm_typeid_base;
  static string typename="";
  static uvm_callbacks_base typeid_map[uvm_typeid_base];
  static uvm_typeid_base type_map[uvm_callbacks_base];
endclass
class uvm_typeid#(type T=uvm_object) extends uvm_typeid_base;
  static uvm_typeid#(T) m_b_inst = get();
  static function uvm_typeid#(T) get();
    if(m_b_inst == null) begin
      m_b_inst = new;
    end
    return m_b_inst;
  endfunction
endclass

// Class - uvm_callbacks_base
//
// Base class singleton that holds generic queues for all instance
// specific objects. This is an internal class. This class contains a
// global pool that has all of the instance specific callback queues in it. 
// All of the typewide callback queues live in the derivative class
// uvm_typed_callbacks#(T). This is not a user visible class.
//
// This class holds the class inheritance hierarchy information
// (super types and derivative types).
//
// Note, all derivative uvm_callbacks#() class singletons access this
// global m_pool object in order to get access to their specific
// instance queue.

class uvm_callbacks_base extends uvm_object;
  static uvm_callbacks_base m_b_inst;
  static uvm_pool#(uvm_object,uvm_queue#(uvm_callback)) m_pool = m_get_pool();
  static function uvm_pool#(uvm_object,uvm_queue#(uvm_callback)) m_get_pool();
    if(m_pool == null) m_pool = new;
    return m_pool;
  endfunction

  //Type checking inteface
  uvm_callbacks_base m_this_type[$];  //one to many T->T/CB
  uvm_typeid_base m_super_type;       //one to one relation 
  uvm_typeid_base m_derived_types[$]; //one to many relation

  virtual function bit m_am_i_a(uvm_object obj);
    return 0;
  endfunction
  virtual function bit m_is_for_me(uvm_callback cb);
    return 0;
  endfunction
  virtual function bit m_is_registered(uvm_object obj, uvm_callback cb);
    return 0;
  endfunction

  //Check registration. To test registration, start at this class and
  //work down the class hierarchy. If any class returns true then
  //the pair is legal.
  function bit check_registration(uvm_object obj, uvm_callback cb);
    uvm_callbacks_base st, dt;
    if(m_is_registered(obj,cb)) begin
      return 1;
    end
    // Need to look at all possible T/CB pairs of this type
    foreach(m_this_type[i]) begin
      if(m_b_inst != m_this_type[i])
        if( m_this_type[i].m_is_registered(obj,cb)) begin
          return 1;
        end
    end

    if(obj == null) begin
      foreach(m_derived_types[i]) begin
        dt = uvm_typeid_base::typeid_map[m_derived_types[i] ];
        if(dt != null && dt.check_registration(null,cb))
          return 1;
      end
    end

    return 0;
  endfunction

  virtual function uvm_queue#(uvm_callback) m_get_twq(uvm_object obj);
    return null;
  endfunction
  virtual function void m_add_tw_cbs(uvm_callback cb, uvm_apprepend ordering);
  endfunction
  virtual function bit m_delete_tw_cbs(uvm_callback cb);
    return 0;
  endfunction

endclass

// Class - uvm_typed_callbacks#(T)
//
// Another internal class. This contains the queue of typewide
// callbacks. It also contains some of the public interface methods,
// but those methods are accessed via the uvm_callbacks#() class
// so they are documented in that class even though the implementation
// is in this class. 
//
// The add, delete, and display methods are implemented in this class.

class uvm_typed_callbacks#(type T=uvm_object) extends uvm_callbacks_base;
  static uvm_queue#(uvm_callback) m_twcb = new("typewide_queue");
  static string m_typename;

  //The actual global object from the derivative class. Note that this is
  //just a reference to the object that is generated in the derived class.
  static uvm_typed_callbacks#(T) m_t_inst;

  static function uvm_queue#(uvm_callback) m_get_tw_queue();
    if(m_t_inst.m_twcb == null) begin
      m_t_inst.m_twcb = new;
    end
    return m_t_inst.m_twcb;
  endfunction

  //Type checking interface
  virtual function bit m_am_i_a(uvm_object obj);
    T this_type;
    if(obj == null) return 1;
    return($cast(this_type,obj));
  endfunction

  //Gettting the typewide queue
  virtual function uvm_queue#(uvm_callback) m_get_twq(uvm_object obj);
    if(m_am_i_a(obj)) begin
      foreach(m_derived_types[i]) begin
        uvm_callbacks_base dt;
        dt = uvm_typeid_base::typeid_map[m_derived_types[i] ];
        if(dt != null && dt != this) begin
          m_get_twq = dt.m_get_twq(obj);
          if(m_get_twq != null) return m_get_twq;
        end
      end
      return m_t_inst.m_twcb;
    end
    else return null;
  endfunction

  static function int m_cb_find(uvm_queue#(uvm_callback) q, uvm_callback cb);
    for(int i=0; i<q.size(); ++i) begin
      if(q.get(i) == cb) return i;
    end
    return -1;
  endfunction

  //For a typewide callback, need to add to derivative types as well.
  virtual function void m_add_tw_cbs(uvm_callback cb, uvm_apprepend ordering);
    uvm_callbacks_base cb_pair;
    uvm_object obj;
    T me;
    uvm_queue#(uvm_callback) q;
    if(m_cb_find(m_t_inst.m_twcb,cb) == -1) begin
      m_t_inst.m_twcb.push_back(cb);
    end
    if(m_t_inst.m_pool.first(obj)) begin
      do begin
        if($cast(me,obj)) begin
          q = m_t_inst.m_pool.get(obj);
          if(m_cb_find(q,cb) == -1) begin
            if(ordering == UVM_APPEND)
              q.push_back(cb);
            else
              q.push_front(cb);
          end
        end
      end while(m_t_inst.m_pool.next(obj));
    end
    foreach(m_derived_types[i]) begin
      cb_pair = uvm_typeid_base::typeid_map[m_derived_types[i] ];
      if(cb_pair != this) begin
        cb_pair.m_add_tw_cbs(cb,ordering);
      end
    end
  endfunction


  //For a typewide callback, need to remove from derivative types as well.
  virtual function bit m_delete_tw_cbs(uvm_callback cb);
    uvm_callbacks_base cb_pair;
    uvm_object obj;
    uvm_queue#(uvm_callback) q;
    int pos = m_cb_find(m_t_inst.m_twcb,cb);

    if(pos != -1) begin
      m_t_inst.m_twcb.delete(pos);
      m_delete_tw_cbs = 1;
    end

    if(m_t_inst.m_pool.first(obj)) begin
      do begin
        q = m_t_inst.m_pool.get(obj);
        pos = m_cb_find(q,cb);
        if(pos != -1) begin
          q.delete(pos);
          m_delete_tw_cbs = 1;
        end
      end while(m_t_inst.m_pool.next(obj));
    end
    foreach(m_derived_types[i]) begin
      cb_pair = uvm_typeid_base::typeid_map[m_derived_types[i] ];
      if(cb_pair != this)
        m_delete_tw_cbs |= cb_pair.m_delete_tw_cbs(cb);
    end
  endfunction


  static function void display_cbs(T obj=null);
    T me;
    uvm_callbacks_base ib = m_t_inst;
    string cbq[$];
    string inst_q[$];
    string mode_q[$];
    uvm_callback cb;
    string blanks = "                             ";
    uvm_object bobj = obj;

    uvm_queue#(uvm_callback) q;
    string tname, str;

    int max_cb_name=0, max_inst_name=0;

    if(m_typename != "") tname = m_typename;
    else if(obj != null) tname = obj.get_type_name();
    else tname = "*";

    q = m_t_inst.m_twcb;
    for(int i=0; i<q.size(); ++i) begin
      cb = q.get(i);
      cbq.push_back(cb.get_name());
      inst_q.push_back("(*)");
      if(cb.is_enabled()) mode_q.push_back("ON");
      else mode_q.push_back("OFF");

      str = cb.get_name();
      max_cb_name = max_cb_name > str.len() ? max_cb_name : str.len();
      str = "(*)";
      max_inst_name = max_inst_name > str.len() ? max_inst_name : str.len();
    end

    if(obj ==null) begin
      if(m_t_inst.m_pool.first(bobj)) begin
        do
          if($cast(me,bobj)) break;
        while(m_t_inst.m_pool.next(bobj));
      end
      if(me != null || m_t_inst.m_twcb.size()) begin
        $display("Registered callbacks for all instances of %s", tname); 
        $display("---------------------------------------------------------------");
      end
      if(me != null) begin
        do begin
          if($cast(me,bobj)) begin
            q = m_t_inst.m_pool.get(bobj);
            for(int i=0; i<q.size(); ++i) begin
              cb = q.get(i);
              cbq.push_back(cb.get_name());
              inst_q.push_back(bobj.get_full_name());
              if(cb.is_enabled()) mode_q.push_back("ON");
              else mode_q.push_back("OFF");
  
              str = cb.get_name();
              max_cb_name = max_cb_name > str.len() ? max_cb_name : str.len();
              str = bobj.get_full_name();
              max_inst_name = max_inst_name > str.len() ? max_inst_name : str.len();
            end
          end
        end while (m_t_inst.m_pool.next(bobj));
      end
      else begin
        $display("No callbacks registered for any instances of type %s", tname);
      end
    end
    else begin
      if(m_t_inst.m_pool.exists(bobj) || m_t_inst.m_twcb.size()) begin
        $display("Registered callbacks for instance %s of %s", obj.get_full_name(), tname); 
        $display("---------------------------------------------------------------");
      end
      if(m_t_inst.m_pool.exists(bobj)) begin
        q = m_t_inst.m_pool.get(bobj);
        for(int i=0; i<q.size(); ++i) begin
          cb = q.get(i);
          cbq.push_back(cb.get_name());
          inst_q.push_back(bobj.get_full_name());
          if(cb.is_enabled()) mode_q.push_back("ON");
          else mode_q.push_back("OFF");

          str = cb.get_name();
          max_cb_name = max_cb_name > str.len() ? max_cb_name : str.len();
          str = bobj.get_full_name();
          max_inst_name = max_inst_name > str.len() ? max_inst_name : str.len();
        end
      end
    end
    if(!cbq.size()) begin
      if(obj == null) str = "*";
      else str = obj.get_full_name();
      $display("No callbacks registered for instance %s of type %s", str, tname);
    end

    foreach (cbq[i]) begin
      $display("%s  %s on %s  %s", cbq[i], blanks.substr(0,max_cb_name-cbq[i].len()-1), inst_q[i], blanks.substr(0,max_inst_name - inst_q[i].len()-1), mode_q[i]);
    end

  endfunction

endclass

//------------------------------------------------------------------------------
//
// CLASS: uvm_callbacks #(T,CB)
//
// The ~uvm_callbacks~ class provides a base class for implementing callbacks,
// which are typically used to modify or augment component behavior without
// changing the component class. To work effectively, the developer of the
// component class defines a set of "hook" methods that enable users to
// customize certain behaviors of the component in a manner that is controlled
// by the component developer. The integrity of the component's overall behavior
// is intact, while still allowing certain customizable actions by the user.
// 
// To enable compile-time type-safety, the class is parameterized on both the
// user-defined callback interface implementation as well as the object type
// associated with the callback. The object type-callback type pair are
// associated together using the <`uvm_register_callback> macro to define
// a valid pairing; valid pairings are checked when a user attempts to add
// a callback to an object.
//
// To provide the most flexibility for end-user customization and reuse, it
// is recommended that the component developer also define a corresponding set
// of virtual method hooks in the component itself. This affords users the ability
// to customize via inheritance/factory overrides as well as callback object
// registration. The implementation of each virtual method would provide the
// default traversal algorithm for the particular callback being called. Being
// virtual, users can define subtypes that override the default algorithm,
// perform tasks before and/or after calling super.<method> to execute any
// registered callbacks, or to not call the base implementation, effectively
// disabling that particalar hook. A demonstration of this methodology is
// provided in an example included in the kit.

class uvm_callbacks#(type T=uvm_object, type CB=uvm_callback)
    extends uvm_typed_callbacks#(T);

  // Parameter: T
  //
  // This type parameter specifies the base object type with which the
  // <CB> callback objects will be registered. This object must be
  // a derivative of ~uvm_object~.

  // Parameter: CB
  //
  // This type parameter specifies the base callback type that will be
  // managed by this callback class. The callback type is typically a
  // interface class, which defines one or more virtual method prototypes 
  // that users can override in subtypes. This type must be a derivative
  // of <uvm_callback>.
  
  typedef uvm_callbacks#(T,CB) this_type;
  typedef uvm_callbacks#(T,uvm_callback) that_type;


   // Singleton instance is used for type checking
  static this_type m_inst;
  static bit b = initialize(); 

  // typeinfo
  static uvm_typeid_base m_typeid = uvm_typeid#(T)::get();
  static uvm_typeid_base m_cb_typeid = uvm_typeid#(CB)::get();

  static string m_typename="";
  static string m_cb_typename="";
  static uvm_report_object reporter = new("cb_tracer");

  // `uvm_object_param_utils(this_type)

  static function this_type get();
    if(m_inst == null) begin
      create_m_inst();
    end
    return m_inst;
  endfunction

  static uvm_callbacks#(T,uvm_callback) m_base_inst;

  static function void create_m_inst();
    //If this is not the base instance, need to get the base instance
    uvm_typeid#(uvm_callback) _cb_base_type = uvm_typeid#(uvm_callback)::get();
    uvm_typeid_base cb_base_type = _cb_base_type;
    uvm_typeid#(CB) _this_cb_type = uvm_typeid#(CB)::get();
    uvm_typeid_base this_cb_type = _this_cb_type;

    m_inst = new;
    m_typeid = uvm_typeid#(T)::get();

    if(cb_base_type == this_cb_type) begin
      $cast(m_base_inst, m_inst);
      // The base inst in the super class gets set to this base inst
      uvm_typed_callbacks#(T)::m_t_inst = m_base_inst;
      // The base inst the most super class gets set to the base inst
      uvm_callbacks_base::m_b_inst = m_base_inst;

      uvm_typeid_base::typeid_map[m_typeid] = m_inst; 
      uvm_typeid_base::type_map[m_b_inst] = m_typeid;
    end

    if(cb_base_type != this_cb_type) begin
      m_base_inst = uvm_callbacks#(T,uvm_callback)::get();
      m_b_inst.m_this_type.push_back(m_inst);
    end

  endfunction

  static function bit initialize();
    create_m_inst();
    assert( m_inst != null );
    return 1;
  endfunction


  // Register valid callback type
  bit m_registered = 0;
  static function bit register_pair(string tname="", cbname="");
    this_type inst = get();

    m_typename = tname;
    uvm_typed_callbacks#(T)::m_typename = tname;
    m_cb_typename = cbname;

    m_typeid.typename = tname;
    m_cb_typeid.typename = cbname;

    inst.m_registered = 1; 

    return 1;
  endfunction

  virtual function bit m_is_registered(uvm_object obj, uvm_callback cb);
    if(m_is_for_me(cb) && m_am_i_a(obj)) begin
      return m_registered;
    end
  endfunction

  //Does type check to see if the callback is valid for this type
  virtual function bit m_is_for_me(uvm_callback cb);
    CB this_cb;
    return($cast(this_cb,cb));
  endfunction

  // Group: Add/delete inteface

  // Function: add
  //
  // Registers the given callback object, ~cb~, with the given
  // ~obj~ handle. The ~obj~ handle can be null, which allows 
  // registration of callbacks without an object context. If
  // ~ordreing~ is UVM_APPEND (default), the callback will be executed
  // after previously added callbacks, else  the callback
  // will be executed ahead of previously added callbacks. The ~cb~
  // is the callback handle; it must be non-null, and if the callback
  // has already been added to the object instance then a warning is
  // issued. Note that the CB parameter is optional. For example, the 
  // following are equivalent:
  //
  //| uvm_callbacks#(my_comp)::add(comp_a, cb);
  //| uvm_callbacks#(my_comp, my_callback)::add(comp_a,cb);

  static function void add(T obj, uvm_callback cb, uvm_apprepend ordering=UVM_APPEND);
    uvm_queue#(uvm_callback) q;
    string nm,tnm; 
    if(cb==null) begin
       if(obj==null) nm = "(*)"; else nm = obj.get_full_name();
       if(m_base_inst.m_typename!="") tnm = m_base_inst.m_typename; else if(obj != null) tnm = obj.get_type_name(); else tnm = "uvm_object";
       uvm_report_error("CBUNREG", { "Null callback object cannot be registered with object ",
         nm, " (", tnm, ")" }, UVM_NONE);
       return;
    end
    if(!m_base_inst.check_registration(obj,cb)) begin
       if(obj==null) nm = "(*)"; else nm = obj.get_full_name();
       if(m_base_inst.m_typename!="") tnm = m_base_inst.m_typename; else if(obj != null) tnm = obj.get_type_name(); else tnm = "uvm_object";
       uvm_report_warning("CBUNREG", { "Callback ", cb.get_name(), " cannot be registered with object ",
         nm, " because callback type ", cb.get_type_name(),
         " is not registered with object type ", tnm }, UVM_NONE);
    end
    if(obj == null) begin
      if(m_cb_find(m_t_inst.m_twcb,cb) != -1) begin
        if(m_base_inst.m_typename!="") tnm = m_base_inst.m_typename; else if(obj != null) tnm = obj.get_type_name(); else tnm = "uvm_object";
        uvm_report_warning("CBPREG", { "Callback object ", cb.get_name(), " is already registered with type ", tnm }, UVM_NONE);
      end
      else begin
        m_t_inst.m_add_tw_cbs(cb,ordering);
      end
    end
    else begin
      q = m_base_inst.m_pool.get(obj);
      if(q.size() == 0)
        for(int i=0; i<m_t_inst.m_twcb.size(); ++i)  begin
          q.push_back(m_t_inst.m_twcb.get(i)); 
        end
      //check if already exists in the queue
      if(m_cb_find(q,cb) != -1) begin
        uvm_report_warning("CBPREG", { "Callback object ", cb.get_name(), " is already registered",
          " with object ", obj.get_full_name() }, UVM_NONE);
      end
      else begin
        if(ordering == UVM_APPEND) begin
          q.push_back(cb);
        end
        else begin
          q.push_front(cb);
        end
      end
    end
  endfunction

  // Function: add_by_name
  //
  // Registers the given callback object, ~cb~, with one or more uvm_components.
  // The components must already exist and must be type T or a derivative. As
  // with <add> the CB parameter is optional. ~root~ specifies the location in
  // the component hierarchy to start the search for ~name~. See <uvm_root::find_all>
  // for more details on searching by name.

  static function void add_by_name(string name, uvm_callback cb,
     uvm_component root, uvm_apprepend ordering=UVM_APPEND);
    uvm_component cq[$];
    T t;
    if(cb==null) begin
       uvm_report_error("CBUNREG", { "Null callback object cannot be registered with object(s) ",
         name }, UVM_NONE);
       return;
    end
    void'(uvm_top.find_all(name,cq,root));
    if(cq.size() == 0) begin
      uvm_report_warning("CBNOMTC", { "add_by_name failed to find any components matching the name ",
        name, ", callback ", cb.get_name(), " will not be registered." }, UVM_NONE);
    end
    foreach(cq[i]) begin
      if($cast(t,cq[i])) begin 
        add(t,cb,ordering); 
      end
    end
  endfunction


  // Function: delete
  //
  // Deletes the given callback object, ~cb~, from the queue associated with
  //  the given ~obj~ handle. The ~obj~ handle can be null, which allows 
  // de-registration of callbacks without an object context. 
  // The ~cb~ is the callback handle; it must be non-null, and if the callback
  // has already been removed to the object instance then a warning is
  // issued. Note that the CB parameter is optional. For example, the 
  // following are equivalent:
  //
  //| uvm_callbacks#(my_comp)::remove(comp_a, cb);
  //| uvm_callbacks#(my_comp, my_callback)::remove(comp_a,cb);

  static function void delete(T obj, uvm_callback cb);
    uvm_object b_obj = obj;
    uvm_queue#(uvm_callback) q;
    bit found = 0;
    int pos;
    if(obj == null) begin
      found = m_t_inst.m_delete_tw_cbs(cb);
    end
    else begin
      q = m_base_inst.m_pool.get(b_obj);
      pos = m_cb_find(q,cb);
      if(pos != -1) begin
        q.delete(pos);
        found = 1;
      end
    end
    if(!found) begin
      string nm;
      if(obj==null) nm = "(*)"; else nm = obj.get_full_name();
      uvm_report_warning("CBUNREG", { "Callback ", cb.get_name(), " cannot be removed from object ",
        nm, " because it is not currently registered to that object." }, UVM_NONE);
    end
  endfunction


  // Function: delete_by_name
  //
  // Removes the given callback object, ~cb~, associated with one or more 
  // uvm_component callback queues. As with <delete> the CB parameter is 
  // optional. ~root~ specifies the location in the component hierarchy to start 
  // the search for ~name~. See <uvm_root::find_all> for more details on searching 
  // by name.

  static function void delete_by_name(string name, uvm_callback cb,
     uvm_component root);
    uvm_component cq[$];
    T t;
    void'(uvm_top.find_all(name,cq,root));
    if(cq.size() == 0) begin
      uvm_report_warning("CBNOMTC", { "delete_by_name failed to find any components matching the name ",
        name, ", callback ", cb.get_name(), " will not be unregistered." }, UVM_NONE);
    end
    foreach(cq[i]) begin
      if($cast(t,cq[i])) begin 
        delete(t,cb); 
      end
    end
  endfunction


  // Group: Iterator interface
  // This set of functions provide an iterator interface for callback queues. A facade
  // class, <uvm_callback_iter> is also available, and is the generally preferred way to
  // iterate over callback queues.

  // Function: get_first
  //
  // returns the first enabled callback of type CB which resides in the queue for ~obj~.
  // If ~obj~ is null then the typewide queue for T is searched. ~itr~ is the iterator;
  // it will be updated with a value that can be supplied to <get_next> to get the next
  // callback object.
  //
  // If the queue is empty then null is returned.

  static function CB get_first (ref int itr, input T obj);
    uvm_queue#(uvm_callback) q;
    CB cb;
    if(!m_base_inst.m_pool.exists(obj)) begin //no instance specific
      if(obj == null) begin
        q = m_t_inst.m_twcb;
      end
      else
        q = m_t_inst.m_get_twq(obj); //get the most derivative queue
    end 
    else begin
      q = m_base_inst.m_pool.get(obj);
    end
    for(itr = 0; itr<q.size(); ++itr) begin
      if($cast(cb, q.get(itr))) begin
        if(cb.callback_mode()) begin
          return cb;
        end
      end
    end
    return null;
  endfunction

  // Function: get_next
  //
  // returns the next enabled callback of type CB which resides in the queue for ~obj~,
  // using ~itr~ as the starting point. If ~obj~ is null then the typewide queue for T 
  // is searched. ~itr~ is the iterator; it will be updated with a value that can be 
  // supplied to <get_next> to get the next callback object.
  //
  // If no more callbacks exist in the queue, then null is returned.

  static function CB get_next (ref int itr, input T obj);
    uvm_queue#(uvm_callback) q;
    CB cb;
    get_next = null;
    if(!m_base_inst.m_pool.exists(obj)) begin //no instance specific
      if(obj == null) 
        q = m_t_inst.m_twcb;
      else 
        q = m_t_inst.m_get_twq(obj); //get the most derivative queue
    end 
    else begin
      q = m_base_inst.m_pool.get(obj);
    end
    for(itr = itr+1; itr<q.size(); ++itr) begin
      if($cast(cb, q.get(itr))) begin
        if(cb.is_enabled()) begin
          return cb;
        end
      end
    end
    return null;
  endfunction

endclass

// This type is not really expected to be used directly by the user, instead they are 
// expected to use the macro `uvm_set_super_type. The sole purpose of this type is to
// allow for setting up of the derived_type/super_type mapping.

class uvm_derived_callbacks#(type T=uvm_object, type ST=uvm_object, type CB=uvm_callback)
    extends uvm_callbacks#(T,CB);

  typedef uvm_derived_callbacks#(T,ST,CB) this_type;
  typedef uvm_callbacks#(T)            this_user_type;
  typedef uvm_callbacks#(ST)           this_super_type;
 
  // Singleton instance is used for type checking
  static this_type m_d_inst = get();
  static this_user_type m_user_inst;
  static this_super_type m_super_inst;

  // typeinfo
  static uvm_typeid_base m_s_typeid = uvm_typeid#(ST)::get();

  static function this_type get();
    m_user_inst = this_user_type::get();
    m_super_inst = this_super_type::get();
    m_s_typeid = uvm_typeid#(ST)::get();

    if(m_d_inst == null) begin
      m_d_inst = new;
    end
    return m_d_inst;
  endfunction

  static function bit register_super_type(string tname="", sname="");
    this_user_type u_inst = this_user_type::get();
    this_type      inst = this_type::get();
    uvm_callbacks_base s_obj;

    this_user_type::m_t_inst.m_typename = tname;

    if(sname != "") m_s_typeid.typename = sname;

    if(u_inst.m_super_type != null) begin
      if(u_inst.m_super_type == m_s_typeid) return 1;
      uvm_report_warning("CBTPREG", { "Type ", tname, " is already registered to super type ", 
        this_super_type::m_t_inst.m_typename, ". Ignoring attempt to register to super type ",
        sname}, UVM_NONE); 
      return 1;
    end
    if(this_super_type::m_t_inst.m_typename == "")
      this_super_type::m_t_inst.m_typename = sname;
    u_inst.m_super_type = m_s_typeid;
    u_inst.m_base_inst.m_super_type = m_s_typeid;
    s_obj = uvm_typeid_base::typeid_map[m_s_typeid];
    s_obj.m_derived_types.push_back(m_typeid);
    return 1;
  endfunction

endclass

//------------------------------------------------------------------------------
// CLASS: uvm_callback_iter
//
// The ~uvm_callback_iter~ class is an iterator class for iterating over
// callback queues of a specific callback type. The typical usage of
// the class is:
//
//| uvm_callback_iter#(mycomp,mycb) iter = new(this);
//| for(mycb cb = iter.first(); cb != null; cb = iter.next())
//|    cb.dosomething();
//
//------------------------------------------------------------------------------

class uvm_callback_iter#(type T = uvm_object, type CB = uvm_callback);

   local int m_i;
   local T   m_obj;
   local CB  m_cb;

   // Function: new
   //
   // Creates a new callback iterator object. It is required that the object
   // context be provided.

   function new(T obj);
      m_obj = obj;
   endfunction

   // Function: first
   //
   // Returns the first valid (enabled) callback of the callback type (or
   // a derivative) that is in the queue of the context object. If the
   // queue is empty then null is returned.

   function CB first();
      m_cb = uvm_callbacks#(T,CB)::get_first(m_i, m_obj);
      return m_cb;
   endfunction

   // Function: next
   //
   // Returns the first valid (enabled) callback of the callback type (or
   // a derivative) that is in the queue of the context object. If the
   // queue is empty then null is returned.

   function CB next();
      m_cb = uvm_callbacks#(T,CB)::get_next(m_i, m_obj);
      return m_cb;
   endfunction

   // Function: get_cb
   //
   // Returns the last callback accessed via a first() or next()
   // call. 

   function CB get_cb();
      return m_cb;
   endfunction

/****
   function void trace(uvm_object obj = null);
      if (m_cb != null && T::cbs::get_debug_flags() & UVM_CALLBACK_TRACE) begin
         uvm_report_object reporter = null;
         string who = "Executing ";
         void'($cast(reporter, obj));
         if (reporter == null) void'($cast(reporter, m_obj));
         if (reporter == null) reporter = uvm_top;
         if (obj != null) who = {obj.get_full_name(), " is executing "};
         else if (m_obj != null) who = {m_obj.get_full_name(), " is executing "};
         reporter.uvm_report_info("CLLBK_TRC", {who, "callback ", m_cb.get_name()}, UVM_LOW);
      end
   endfunction
****/
endclass



//------------------------------------------------------------------------------
// CLASS: uvm_callback
//
// The ~uvm_callback~ class is the base class for user-defined callback classes.
// Typically, the component developer defines an application-specific callback
// class that extends from this class. In it, he defines one or more virtual
// methods, called a ~callback interface~, that represent the hooks available
// for user override. 
//
// Methods intended for optional override should not be declared ~pure.~ Usually,
// all the callback methods are defined with empty implementations so users have
// the option of overriding any or all of them.
//
// The prototypes for each hook method are completely application specific with
// no restrictions.
//------------------------------------------------------------------------------

class uvm_callback extends uvm_object;

  static uvm_report_object reporter = new("cb_tracer");

  protected bit m_enabled = 1;

  // Function: new
  //
  // Creates a new uvm_callback object, giving it an optional ~name~.

  function new(string name="uvm_callback");
    super.new(name);
  endfunction

  // Function: callback_mode
  //
  // Enable/disable callbacks (modeled like rand_mode and constraint_mode).

  function bit callback_mode(int on=-1);
    `uvm_cb_trace_noobj(this,$sformatf("callback_mode(%0d) %s (%s)",
                         on, get_name(), get_type_name()))
    callback_mode = m_enabled;
    if(on==0) m_enabled=0;
    if(on==1) m_enabled=1;
  endfunction

  // Function: is_enabled
  //
  // Returns 1 if the callback is enabled, 0 otherwise.

  function bit is_enabled();
    return m_enabled;
  endfunction

  static string type_name = "uvm_callback";

  // Function: get_type_name
  //
  // Returns the type name of this callback object.

  virtual function string get_type_name();
     return type_name;
  endfunction

endclass


`endif // UVM_CALLBACK_SVH


