(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2016.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

let error_encoding =
  let open Data_encoding in
  describe
    ~description:
      "The full list of error is available with \
       the global RPC `/errors`"
    (conv
       (fun exn -> `A (List.map json_of_error exn))
       (function `A exns -> List.map error_of_json exns | _ -> [])
       json)

let wrap_tzerror encoding =
  let open Data_encoding in
  union [
    case
      (obj1 (req "ok" encoding))
      (function Ok x -> Some x | _ -> None)
      (fun x -> Ok x) ;
    case
      (obj1 (req "error" error_encoding))
      (function Error x -> Some x | _ -> None)
      (fun x -> Error x) ;
  ]

module Forge = struct
  let block custom_root =
    let open Data_encoding in
    RPC.service
      ~description: "Forge a block"
      ~input:
        (merge_objs
           (obj4
              (req "net_id" Net_id.encoding)
              (req "predecessor" Block_hash.encoding)
              (req "timestamp" Time.encoding)
              (req "fitness" Fitness.encoding))
           Data.Command.encoding)
      ~output: (obj1 (req "payload" bytes))
      RPC.Path.(custom_root / "helpers" / "forge" / "block")
end

let int64_to_bytes i =
  let b = MBytes.create 8 in
  MBytes.set_int64 b 0 i;
  b

let operations =
  Operation_list_list_hash.compute [Operation_list_hash.empty]

let rpc_services : Context.t RPC.directory =
  let dir = RPC.empty in
  let dir =
    RPC.register
      dir
      (Forge.block RPC.Path.root)
      (fun _ctxt ((net_id, predecessor, timestamp, fitness), command) ->
         let shell = { Updater.net_id ; predecessor ; timestamp ; fitness ;
                       operations } in
         let bytes = Data.Command.forge shell command in
         RPC.Answer.return bytes) in
  dir
