# Practical RPC - Rpc framework
# GNU Lesser General Public License, version 2.1
#
# Copyright © 2020 Trey Cutter <treycutter@protonmail.com>

import tables, asyncHttpServer, asyncdispatch, json, strutils
import ./service except HttpCode

type
  RpcServer* = ref object of RootObj
    port: int
    server: AsyncHttpServer
    services*: Table[string, RpcService]

proc register*(self: RpcServer, service: RpcService) =
  service.init()
  self.services.add(service.name, service)

proc start*(self: RpcServer, port: int) =
  self.server = new_async_http_server()
  self.port = port

  proc cb(req: Request) {.async.} =
    echo $req.hostname & " - " & $req.url.path
    var path = $req.url.path
    var service = self.services[path.split(".")[0]]
    var res = parse_json(req.body)
    var response = service.call_rpc(path.split(".")[1], res)
    await req.respond(response.http_code, response.response)

  waitFor self.server.serve(Port(port), cb)
