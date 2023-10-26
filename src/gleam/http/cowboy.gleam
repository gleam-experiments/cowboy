import gleam/list
import gleam/pair
import gleam/map.{Map}
import gleam/option.{None, Option, Some}
import gleam/result
import gleam/http.{Header}
import gleam/http/service.{Service}
import gleam/http/request.{Request}
import gleam/bit_builder.{BitBuilder}
import gleam/dynamic.{Dynamic}
import gleam/erlang/process.{Pid}

type CowboyRequest

@external(erlang, "gleam_cowboy_native", "start_link")
fn erlang_start_link(
  handler: fn(CowboyRequest) -> CowboyRequest,
  port: Int,
) -> Result(Pid, Dynamic)

@external(erlang, "cowboy_req", "reply")
fn cowboy_reply(
  a: Int,
  b: Map(String, Dynamic),
  c: BitBuilder,
  d: CowboyRequest,
) -> CowboyRequest

@external(erlang, "cowboy_req", "method")
fn erlang_get_method(a: CowboyRequest) -> Dynamic

fn get_method(request) -> http.Method {
  request
  |> erlang_get_method
  |> http.method_from_dynamic
  |> result.unwrap(http.Get)
}

@external(erlang, "cowboy_req", "headers")
fn erlang_get_headers(a: CowboyRequest) -> Map(String, String)

fn get_headers(request) -> List(http.Header) {
  request
  |> erlang_get_headers
  |> map.to_list
}

@external(erlang, "gleam_cowboy_native", "read_entire_body")
fn get_body(a: CowboyRequest) -> #(BitString, CowboyRequest)

@external(erlang, "cowboy_req", "scheme")
fn erlang_get_scheme(a: CowboyRequest) -> String

fn get_scheme(request) -> http.Scheme {
  request
  |> erlang_get_scheme
  |> http.scheme_from_string
  |> result.unwrap(http.Http)
}

@external(erlang, "cowboy_req", "qs")
fn erlang_get_query(a: CowboyRequest) -> String

fn get_query(request) -> Option(String) {
  case erlang_get_query(request) {
    "" -> None
    query -> Some(query)
  }
}

@external(erlang, "cowboy_req", "path")
fn get_path(a: CowboyRequest) -> String

@external(erlang, "cowboy_req", "host")
fn get_host(a: CowboyRequest) -> String

@external(erlang, "cowboy_req", "port")
fn get_port(a: CowboyRequest) -> Int

fn proplist_get_all(input: List(#(a, b)), key: a) -> List(b) {
  list.filter_map(
    input,
    fn(item) {
      case item {
        #(k, v) if k == key -> Ok(v)
        _ -> Error(Nil)
      }
    },
  )
}

// In cowboy all header values are strings except set-cookie, which is a
// list. This list has a special-case in Cowboy so we need to set it
// correctly.
// https://github.com/gleam-lang/cowboy/issues/3
fn cowboy_format_headers(headers: List(Header)) -> Map(String, Dynamic) {
  let set_cookie_headers = proplist_get_all(headers, "set-cookie")
  headers
  |> list.map(pair.map_second(_, dynamic.from))
  |> map.from_list
  |> map.insert("set-cookie", dynamic.from(set_cookie_headers))
}

fn service_to_handler(
  service: Service(BitString, BitBuilder),
) -> fn(CowboyRequest) -> CowboyRequest {
  fn(request) {
    let #(body, request) = get_body(request)
    let response =
      service(Request(
        body: body,
        headers: get_headers(request),
        host: get_host(request),
        method: get_method(request),
        path: get_path(request),
        port: Some(get_port(request)),
        query: get_query(request),
        scheme: get_scheme(request),
      ))
    let status = response.status

    let headers = cowboy_format_headers(response.headers)
    let body = response.body
    cowboy_reply(status, headers, body, request)
  }
}

// TODO: document
// TODO: test
pub fn start(
  service: Service(BitString, BitBuilder),
  on_port number: Int,
) -> Result(Pid, Dynamic) {
  service
  |> service_to_handler
  |> erlang_start_link(number)
}
