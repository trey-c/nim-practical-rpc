# Practical RPC - Rpc framework
# GNU Lesser General Public License, version 2.1
#
# Copyright © 2020 Trey Cutter <treycutter@protonmail.com>

import httpclient, json, macros, strutils

type
  RpcClient* = ref object of RootObj
    client*: AsyncHttpClient
    url*: string
    path*: string

proc init*(self: RpcClient) =
  self.client = new_async_http_client()

template make_request*(self: RpcClient, url, payload: string,
    callback: untyped) =
  echo "Requesting " & url

  self.client.headers = newHttpHeaders({"Content-Type": "application/json"})
  let response {.inject.} = self.client.request(url, httpMethod = HttpPost,
    body = payload)

  callback

proc add*[T](j: JsonNode, s: string, i: T) =
  json.add(j, s, %i)

proc def_rpc_client_call*(client_name, method_name, url: string,
                          req, res: NimNode): NimNode =
  let self = ident(client_name)
  let proc_name = nnkPostfix.new_tree(
        new_ident_node("*"),
        new_ident_node(method_name)
  )

  let
    mn = url & "." & method_name
  var
    service_name = client_name
    unmarshal = "rpc_unmarshal"
    marshal = "rpc_marshal"

  service_name.remove_suffix("Client")
  var runmarshal = ident(unmarshal & service_name)
  var rmarshal = ident(marshal & service_name)
  result = quote do:
    template `proc_name`(self: `self`, payload: `req`,
        callback: untyped) =
      var str_payload = $`rmarshal`(payload)
      var u = self.url & `mn`
      self.make_request(u, str_payload):
        response.add_callback(
          proc () =
          var r = response.read
          var body = parse_json(r.body.read)
          echo "Received " & u & " -> " & $code(r)
          var res {.inject.}: `res`
          `runmarshal`(body, addr(res))
          callback
        )

