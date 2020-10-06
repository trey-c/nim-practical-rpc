# Practical RPC - Rpc framework
# GNU Lesser General Public License, version 2.1
#
# Copyright © 2020 Trey Cutter <treycutter@protonmail.com>

import ./utils
include "../practical_rpc/service.nim"

rpc_service "MockService", "/mock":
  count: int
  max: int

  rpc_proc "test_one":
    request:
      name: string
    response:
      greeting: string
  do:
    result.greeting = "Hello, " & request.name
    code = Http200

  rpc_proc "test_two":
    request:
      id: int
      name: string
      age: int
    response:
      id: int
      person: tuple[
        name: string,
        age: int
      ]
  do:
    result.id = request.id
    result.person = (name: request.name, age: request.age)
    code = Http200

  rpc_proc "test_three":
    request:
      wanted_age: int
    response:
      people_List: seq[tuple[
        name: string,
        age: int
      ]]
  do:
    for i in self.count..self.max:
      result.people_list.add((name: "Testers", age: request.wanted_age))
    code = Http200

block:
  var
    mock = MockService(count: 1, max: 15)
    http_code = Http404

  expect(mock.test_one((name: "World"), http_code).greeting == "Hello, World")
  expect(http_code == Http200)

  var test_two = mock.test_two((id: 1, name: "Tester", age: 27), http_code)
  expect(test_two.id == 1)
  expect(test_two.person.name == "Tester")
  expect(test_two.person.age == 27)
  expect(http_code == Http200)

  expect(mock.test_three((wanted_age: 5), http_code).people_list.len == 15)
  expect(http_code == Http200)

