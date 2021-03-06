(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2016.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

type error += Parsing_error
type error += Invalid_signature

let () =
  register_error_kind
    `Permanent
    ~id:"parsing_error"
    ~title:"Parsing error"
    ~description:"Raised when a block header has not been parsed correctly"
    ~pp:(fun ppf () -> Format.fprintf ppf "Block header parsing error")
    Data_encoding.empty
    (function Parsing_error -> Some () | _ -> None)
    (fun () -> Parsing_error)

let () =
  register_error_kind
    `Permanent
    ~id:"invalid_signature"
    ~title:"Invalid signature"
    ~description:"Raised when the provided signature is invalid"
    ~pp:(fun ppf () -> Format.fprintf ppf "Invalid signature")
    Data_encoding.empty
    (function Invalid_signature -> Some () | _ -> None)
    (fun () -> Invalid_signature)

type operation = ()
let max_operation_data_length = 0
let parse_operation _h _op = Error []
let max_number_of_operations = 0

type block = {
  shell: Updater.shell_block ;
  command: Data.Command.t ;
  signature: Ed25519.Signature.t ;
}

let max_block_length =
  match Data_encoding.Binary.fixed_length Data.Command.signed_encoding with
  | None -> assert false
  | Some len -> len

let parse_block { Updater.shell ; proto } _pred_timestamp : block tzresult =
  match Data_encoding.Binary.of_bytes Data.Command.signed_encoding proto with
  | None -> Error [Parsing_error]
  | Some (command, signature) -> Ok { shell ; command ; signature }

let check_signature ctxt { shell ; command ; signature } =
  let bytes = Data.Command.forge shell command in
  Data.Pubkey.get_pubkey ctxt >>= fun public_key ->
  fail_unless
    (Ed25519.Signature.check public_key signature bytes)
    Invalid_signature

let apply ctxt header _ops =
  check_signature ctxt header >>=? fun () ->
  Data.Init.may_initialize ctxt >>=? fun ctxt ->
  Context.set_fitness ctxt header.shell.fitness >>= fun ctxt ->
  match header.command with
  | Activate hash ->
      let commit_message =
        Format.asprintf "activate %a" Protocol_hash.pp_short hash in
      Context.set_commit_message ctxt commit_message >>= fun ctxt ->
      Updater.activate ctxt hash >>= fun ctxt ->
      return ctxt
  | Activate_testnet hash ->
      let commit_message =
        Format.asprintf "activate testnet %a" Protocol_hash.pp_short hash in
      Context.set_commit_message ctxt commit_message >>= fun ctxt ->
      Updater.set_test_protocol ctxt hash >>= fun ctxt ->
      Updater.fork_test_network ctxt >>= fun ctxt ->
      return ctxt

let preapply ctxt _block_pred _sort _ops =
  return ( ctxt,
           { Updater.applied = [] ;
             refused = Operation_hash.Map.empty ;
             branch_refused = Operation_hash.Map.empty ;
             branch_delayed = Operation_hash.Map.empty ;
           } )

let rpc_services = Services.rpc_services

let configure_sandbox = Data.Init.configure_sandbox
