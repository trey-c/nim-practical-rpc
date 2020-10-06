# Practical RPC - Rpc framework
# GNU Lesser General Public License, version 2.1
#
# Copyright © 2020 Trey Cutter <treycutter@protonmail.com>

import macros, json, algorithm, asynchttpserver
import ./client

export HttpCode

type
  RpcService* = ref object of RootObj
    name*: string
  CallRpc* = tuple[response: string, http_code: HttpCode]

method init*(self: RpcService) {.base.} =
  echo("Override me - init")

method call_rpc*(self: RpcService, name: string, payload: JsonNode): string {.base.} =
  echo("Override me - call_rpc")

proc marshal_tup(stmt_list, tup, iresult, x: NimNode) =
  if tup.kind == nnkBracketExpr and tup[1].kind == nnkTupleTy:
    var
      stmt = new_stmt_list()
      oaname = ident("aobject")
      t = ident("t")
    marshal_tup(stmt, tup[1], oaname, t)
    stmt_list.add quote do:
      for `t` in `x`:
        var `oaname` = new_j_object()
        `stmt`
        `iresult`.add(`oaname`)
    return

  for def in tup:
    if def[0].kind == nnkIdent and def[1].kind == nnkIdent:
      var
        keyname = def[0]
        keynamelit = def[0].str_val
      stmt_list.add quote do:
        `iresult`.add(`keynamelit`, `x`.`keyname`)
    elif def[0].kind == nnkIdent and def[1].kind == nnkTupleTy:
      var
        oname = def[0]
        onamelit = oname.str_val
        call = nnkDotExpr.new_tree(iresult, ident("add"))
      stmt_list.add quote do:
        var `oname` = new_j_object()
        `call`(`onamelit`, `oname`)

      marshal_tup(stmt_list, def[1], oname, nnkDotExpr.new_tree(x, oname))
    elif def[0].kind == nnkIdent and def[1].kind == nnkBracketExpr:
      var
        array_name = def[0]
        array_name_lit = def[0].str_val
      stmt_list.add quote do:
        var `array_name` = new_j_array()

      marshal_tup(stmt_list, def[1], array_name, nnkDotExpr.new_tree(x, def[0]))
      stmt_list.add quote do:
        `iresult`.add(`array_name_lit`, `array_name`)


proc rpc_marshal_def(tup: NimNode, name: string): NimNode =
  var
    x = ident("x")
    iresult = ident("result")
    marshal = ident("rpc_marshal_" & name)
  result = quote do:
    proc `marshal`*(`x`: `tup`): JsonNode =
      `iresult` = new_j_object()

  marshal_tup(result[6], tup, iresult, x)

proc get_key*(t: string, brackets: NimNode): NimNode {.compileTime.} =
  case t
  of "int":
    result = quote do:
      `brackets`.get_int()
  of "string":
    result = quote do:
      `brackets`.get_str()
  of "bool":
    result = quote do:
      `brackets`.get_bool()
  of "float":
    result = quote do:
      `brackets`.get_float()
  else:
    echo "UNKNOWN TYPE IN RPC TUPLE: " & t

proc unmarshal_tup(stmt_list, tup, dots, j: NimNode) =
  if tup.kind == nnkBracketExpr and tup[1].kind == nnkTupleTy:
    var
      stmt = new_stmt_list()
      jarray = ident("jarray")
      t = ident("t")
      tt = tup[1]
      rdots = dots.copy
      jt = rdots[1].str_val
    dots[0] = t
    dots[1] = new_empty_node()
    unmarshal_tup(stmt, tup[1], dots, jarray)
    stmt_list.add quote do:
      for `jarray` in `j`[`jt`].get_elems():
        var `t`: `tt`
        `stmt`
        `rdots`.add(`t`)
    return

  for def in tup:
    if def[0].kind == nnkIdent and def[1].kind == nnkIdent:
      var dot: NimNode

      if dots.kind == nnkDotExpr and dots[1].kind == nnkEmpty:
        dot = dots.copy
        dot[1] = def[0]
      else:
        dot = nnkDotExpr.new_tree(dots, def[0])

      var
        pnode: NimNode = dot
        pnodes: seq[NimNode]
      while true:
        if pnode.kind != nnkDotExpr:
          break
        if pnode[0].kind == nnkDotExpr:
          pnodes.add(pnode)
          pnode = pnode[0]
        elif pnode[0].kind == nnkIdent:
          pnodes.add(pnode)
          break

      var
        prev_bracket: NimNode
        brackets = nnkBracketExpr.new_tree()
      for pn in pnodes.reversed():
        if pn[1].kind == nnkEmpty:
          prev_bracket = j
          continue

        if pn[0].kind == nnkIdent:
          brackets = nnkBracketExpr.new_tree(j, new_lit(pn[1].str_val))
          prev_bracket = brackets
        else:
          brackets = nnkBracketExpr.new_tree(prev_bracket, new_lit(pn[1].str_val))
          prev_bracket = brackets

      stmt_list.add(nnkAsgn.new_tree(dot, get_key(def[1].str_val, brackets)))
    elif def[0].kind == nnkIdent and def[1].kind == nnkTupleTy:
      unmarshal_tup(stmt_list, def[1], nnkDotExpr.new_tree(dots, def[0]), j)
    elif def[0].kind == nnkIdent and def[1].kind == nnkBracketExpr:
      unmarshal_tup(stmt_list, nnkBracketExpr.new_tree(dots, def[1][1]),
          nnkDotExpr.new_tree(dots, def[0]), j)

proc rpc_unmarshal_def(tup: NimNode, name: string): NimNode =
  var
    j = ident("j")
    t = ident("tup")
    unmarshal = ident("rpc_unmarshal_" & name)
  result = quote do:
    proc `unmarshal`*(`j`: JsonNode, `t`: ptr `tup`) =
      var tmp = 1

  unmarshal_tup(result[6], tup, t, j)

proc def_rpc_service_type(name: string, params: NimNode): NimNode =
  result = nnkTypeDef.new_tree(
    nnkPostfix.new_tree(
        new_ident_node("*"),
        new_ident_node(name)
    ),
    new_empty_node(),
    nnkRefTy.new_tree(
      nnkObjectTy.new_tree(
        new_empty_node(),
        nnkOfInherit.newTree(
          new_ident_node("RpcService")
    ),
    nnkRecList.new_tree()
  )
    )
  )

  for param in params:
    result[2][0][2].add(nnkIdentDefs.new_tree(
        nnkPostfix.new_tree(
          new_ident_node("*"),
          new_ident_node(param[0].str_val)
      ),
      new_ident_node(param[1][0].str_val),
      new_empty_node()
    )
    )


proc call_rpc_branch_def(name, service: string,
    request_tuple, response_tuple: NimNode): NimNode =
  var
    ident_req = ident("req_tup")
    ident_http_code = ident("http_code")
    method_call = nnkCall.new_tree(
      nnkDotExpr.new_tree(
        ident("self"),
        ident(name)
      ),
      ident_req,
      ident_http_code
      )

  var
    unmarshal = ident("rpc_unmarshal_" & service)
    marshal = ident("rpc_marshal_" & service)
  result = quote do:
    var `ident_http_code`: HttpCode = Http404
    var `ident_req`: `request_tuple`
    `unmarshal`(payload, addr(`ident_req`))
    result.response = $`marshal`(`method_call`)
    result.http_code = `ident_http_code`

proc call_rpc_def(service: string, proc_table: seq[tuple[name: string,
    request_tuple, response_tuple: NimNode]]): NimNode =
  var
    call = new_stmt_list()
    ifstmt = nnkIfStmt.new_tree()

  for p in proc_table:
    var branch = nnkElifBranch.newTree(
      nnkInfix.newTree(
        newIdentNode("=="),
        newIdentNode("name"),
        newLit(p.name)
      ),
      call_rpc_branch_def(p.name, service, p.request_tuple, p.response_tuple)
    )
    ifstmt.add(branch)


  call.add(ifstmt)
  result = nnkMethodDef.new_tree(
      nnkPostfix.new_tree(
        new_ident_node("*"),
        new_ident_node("call_rpc")
    ),
    new_empty_node(),
    new_empty_node(),
    nnkFormalParams.new_tree(
      new_ident_node("CallRpc"),
      nnkIdentDefs.new_tree(
        new_ident_node("self"),
        new_ident_node(service),
        new_empty_node()
      ),
      nnkIdentDefs.new_tree(
        new_ident_node("name"),
        new_ident_node("string"),
        new_empty_node()
      ),
      nnkIdentDefs.new_tree(
        new_ident_node("payload"),
        new_ident_node("JsonNode"),
        new_empty_node()
      ),
    ),
    new_empty_node(),
    new_empty_node(),
    call
  )

proc rpc_tuple_def(calls: NimNode): NimNode =
  result = nnkTupleTy.new_tree()

  for call in calls:
    var t: NimNode

    if call[1][0].kind == nnkTupleTy or call[1][0].kind == nnkBracketExpr:
      t = call[1][0]
    else:
      t = new_ident_node(call[1][0].str_val)

    result.add(
      nnkIdentDefs.new_tree(
      new_ident_node(call[0].str_val),
      t,
      new_empty_node(),
    ))

proc rpc_proc_def(name, service: string, request_tuple, response_tuple,
    call: NimNode): NimNode =
  result = nnkProcDef.new_tree(
      nnkPostfix.new_tree(
        new_ident_node("*"),
        new_ident_node(name)
    ),
    new_empty_node(),
    new_empty_node(),
    nnkFormalParams.new_tree(
      response_tuple,
      nnkIdentDefs.new_tree(
        new_ident_node("self"),
        new_ident_node(service),
        new_empty_node()
      ),
      nnkIdentDefs.new_tree(
        new_ident_node("request"),
        request_tuple,
        new_empty_node()
      ),
      nnkIdentDefs.new_tree(
        ident("code"),
        nnkVarTy.new_tree(
          ident("HttpCode")
        ),
        new_empty_node()
      )
    ),
    new_empty_node(),
    new_empty_node(),
    call
  )

var tup_list {.compileTime.}: seq[NimNode]

macro rpc_service*(name: string, path: string, body: untyped): untyped =
  tup_list.set_len(0)
  var
    stmt_list = new_stmt_list()
    params = new_stmt_list()
    proc_table: seq[tuple[name: string, request_tuple, response_tuple: NimNode]]
    client_name = name.str_val & "Client"
    client_procs = new_stmt_list()

  for node in body:
    if node.kind == nnkCall:
      params.add(node)
  stmt_list.add(
    nnkTypeSection.new_tree(
      def_rpc_service_type(name.str_val, params),
      nnkTypeDef.new_tree(
        nnkPostfix.new_tree(
          new_ident_node("*"),
          new_ident_node(client_name)
    ),
    new_empty_node(),
      nnkRefTy.new_tree(
        nnkObjectTy.new_tree(
          new_empty_node(),
          nnkOfInherit.newTree(
            new_ident_node("RpcClient")
  ),
    nnkRecList.new_tree()
  )
    )
  )
    )
  )

  var req_marshal, res_marshal, req_unmarshal, res_unmarshal = new_stmt_list()
  for node in body:
    if node.kind == nnkCommand:
      var
        request_tuple = rpc_tuple_def(node[2][0][1])
        response_tuple = rpc_tuple_def(node[2][1][1])

      if tup_list.contains(request_tuple) == false:
        req_marshal.add(rpc_marshal_def(request_tuple, name.str_val))
        req_unmarshal.add(rpc_unmarshal_def(request_tuple, name.str_val))
      if tup_list.contains(response_tuple) == false:
        res_marshal.add(rpc_marshal_def(response_tuple, name.str_val))
        res_unmarshal.add(rpc_unmarshal_def(response_tuple, name.str_val))

      tup_list.add(request_tuple)
      tup_list.add(response_tuple)
      stmt_list.add(rpc_proc_def(node[1].str_val, name.str_val, request_tuple,
          response_tuple, node[3]))
      proc_table.add((name: node[1].str_val, request_tuple: request_tuple,
          response_tuple: response_tuple))
      client_procs.add(def_rpc_client_call(client_name, node[1].str_val,
          path.str_val, request_tuple, response_tuple))

  var
    call_rpc = call_rpc_def(name.str_val, proc_table)
    n = ident(name.str_val)

  result = quote do:
    import json, asyncdispatch
    import client
    `stmt_list`
    `client_procs`
    `req_marshal`
    `res_marshal`
    `req_unmarshal`
    `res_unmarshal`
    `call_rpc`
    method init*(self: `n`) =
      self.name = `path`
