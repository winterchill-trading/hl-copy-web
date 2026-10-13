(** Wire types of the copy-trading HTTP API.

    The API server (hl-copy-api) and this web app both use these types, so a field change
    here is a protocol change: add optional fields with a default, never rename or remove
    one in place. Every type derives [sexp] for logs and journals and [yojson] for the
    HTTP bodies.

    Two conventions come from the browser build. js_of_ocaml compiles OCaml [int] to a
    32-bit integer, so timestamps and nonces (milliseconds since the epoch, about [2^40])
    are [float]s ({!Time_ms}); a float holds every integer below [2^53] exactly. Money
    amounts are USD [float]s meant for display and form input: the engine converts them to
    fixed-point decimals before it sizes an order. *)

open! Core

(** A lowercase hex wallet address, [0x] followed by 40 hex digits. *)
module Address : sig
  type t = private string [@@deriving compare, equal, hash, sexp, yojson]

  (** Lowercases. Raises on anything that is not [0x] plus 40 hex digits. *)
  val of_string : string -> t

  val of_string_opt : string -> t option
  val to_string : t -> string

  (** [0x1234...abcd], for tables. *)
  val short : t -> string
end

(** Milliseconds since the Unix epoch. Encoded as a JSON integer; decoding also accepts a
    JSON float. *)
module Time_ms : sig
  type t = float [@@deriving compare, equal, sexp, yojson]
end

(** JSON ["buy"] and ["sell"]. *)
module Side : sig
  type t =
    | Buy
    | Sell
  [@@deriving compare, enumerate, equal, sexp, yojson]
end

(** The components of a leader's score, as computed by [Hl_copy_core.Score]. *)
module Score_breakdown : sig
  type t =
    { pnl : float (** USD, over the scoring history *)
    ; roi : float (** [pnl] over the starting equity *)
    ; max_drawdown : float (** fraction of peak equity, [0.] to [1.] *)
    ; win_rate : float (** fraction of position-reducing fills that made money *)
    ; trade_count : int
    ; avg_hold_secs : float
    ; consistency : float (** share of scoring windows with positive pnl, [0.] to [1.] *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** Leaderboard pnl per window, USD. *)
module Window_pnl : sig
  type t =
    { day : float
    ; week : float
    ; month : float
    ; all_time : float
    }
  [@@deriving compare, equal, sexp, yojson]
end

module Leader : sig
  type t =
    { address : Address.t
    ; display_name : string option (** absent or [null] when the leader set none *)
    ; rank : int (** 1 is best *)
    ; score : float (** [0.] to [100.] *)
    ; breakdown : Score_breakdown.t
    ; account_value : float (** USD *)
    ; window_pnl : Window_pnl.t
    ; followers : int (** followers on this platform *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** [GET /leaders] *)
module Leaders_response : sig
  type t =
    { as_of : Time_ms.t
    ; leaders : Leader.t list (** sorted by [rank] *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

module Equity_point : sig
  type t =
    { time : Time_ms.t
    ; equity : float (** USD account value *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

module Fill : sig
  type t =
    { time : Time_ms.t
    ; coin : string
    ; side : Side.t
    ; px : float
    ; sz : float (** unsigned *)
    ; closed_pnl : float (** USD, as Hyperliquid reports it *)
    ; fee : float (** USD *)
    ; dir : string (** Hyperliquid's ["Open Long"], ["Close Short"], ... *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

module Position : sig
  type t =
    { coin : string
    ; size : float (** signed: positive is long *)
    ; entry_px : float
    ; unrealized_pnl : float (** USD *)
    ; leverage : float
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** [GET /leaders/<address>] *)
module Leader_detail : sig
  type t =
    { leader : Leader.t
    ; equity_curve : Equity_point.t list (** oldest first *)
    ; fills : Fill.t list (** newest first *)
    ; positions : Position.t list
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** How a follower's target position is derived from the leader's.

    JSON: [{"kind":"equity_ratio"}], [{"kind":"multiplier","value":0.5}],
    [{"kind":"fixed_notional","value":1000}]. *)
module Scale_mode : sig
  type t =
    | Equity_ratio (** leader size times follower equity over leader equity *)
    | Multiplier of float (** leader size times a constant *)
    | Fixed_notional of float
    (** every leader position becomes this much USD notional, same direction *)
  [@@deriving compare, equal, sexp, yojson]

  val to_string_hum : t -> string
end

(** Risk caps applied after scaling. A cap of [0.] means no cap. *)
module Caps : sig
  type t =
    { max_leverage : float
    ; max_notional_per_symbol : float (** USD *)
    ; max_daily_loss : float (** USD; the follow pauses when it is hit *)
    ; allowlist : string list (** coins to copy; empty copies every coin *)
    ; min_order_notional : float (** USD; smaller adjustments are skipped *)
    }
  [@@deriving compare, equal, sexp, yojson]

  (** 3x leverage, 5000 USD per symbol, 500 USD daily loss, every coin, 10 USD minimum. *)
  val default : t
end

(** Wallet login: the server issues a challenge, the wallet signs [message] with
    [personal_sign] (EIP-191), and the signature buys a session token. *)
module Auth : sig
  (** [POST /auth/challenge] *)
  module Challenge_request : sig
    type t = { address : Address.t } [@@deriving compare, equal, sexp, yojson]
  end

  module Challenge : sig
    type t =
      { message : string (** the exact text to sign *)
      ; nonce : string
      ; expires_at : Time_ms.t
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** [POST /auth/verify] *)
  module Verify_request : sig
    type t =
      { address : Address.t
      ; nonce : string (** from the {!Challenge} that was signed *)
      ; signature : string (** [0x]-prefixed 65-byte hex *)
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** The reply to [POST /auth/verify]; send [token] as [Authorization: Bearer <token>]. *)
  module Session : sig
    type t =
      { token : string
      ; address : Address.t
      ; expires_at : Time_ms.t
      }
    [@@deriving compare, equal, sexp, yojson]
  end
end

(** JSON ["Mainnet"] and ["Testnet"], Hyperliquid's [hyperliquidChain] field. *)
module Hyperliquid_chain : sig
  type t =
    | Mainnet
    | Testnet
  [@@deriving compare, equal, sexp, yojson]

  val to_string : t -> string
end

(** Hyperliquid's [approveAgent] user-signed action. The server generates the agent key
    and fills this in; the user's wallet signs {!typed_data} with [eth_signTypedData_v4]. *)
module Approve_agent : sig
  type t =
    { hyperliquid_chain : Hyperliquid_chain.t
    ; signature_chain_id : string
    (** hex chain id the wallet signs under, e.g. ["0x66eee"]; wallets refuse a chain id
        other than the one they are connected to, so the browser may override it *)
    ; agent_address : Address.t
    ; agent_name : string
    ; nonce : Time_ms.t
    }
  [@@deriving compare, equal, sexp, yojson]

  (** The EIP-712 typed data, domain [HyperliquidSignTransaction] version 1, primary type
      [HyperliquidTransaction:ApproveAgent]. *)
  val typed_data : t -> Yojson.Safe.t
end

(** Hyperliquid's optional [approveBuilderFee] user-signed action. *)
module Approve_builder_fee : sig
  type t =
    { hyperliquid_chain : Hyperliquid_chain.t
    ; signature_chain_id : string
    ; max_fee_rate : string (** e.g. ["0.01%"] *)
    ; builder : Address.t
    ; nonce : Time_ms.t
    }
  [@@deriving compare, equal, sexp, yojson]

  (** Primary type [HyperliquidTransaction:ApproveBuilderFee]. *)
  val typed_data : t -> Yojson.Safe.t
end

(** The reply to [POST /agent/new] (authenticated, empty body): a freshly generated agent
    for this user and, when the platform charges one, the builder fee to approve. *)
module Agent_offer : sig
  type t =
    { approve_agent : Approve_agent.t
    ; approve_builder_fee : Approve_builder_fee.t option
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** [POST /agent/approved]: the action exactly as signed (including a chain id the browser
    replaced) and the wallet's signature. The server submits it to Hyperliquid. *)
module Agent_approval : sig
  type t =
    { approve_agent : Approve_agent.t
    ; signature : string
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** [POST /builder-fee], like {!Agent_approval}. *)
module Builder_fee_approval : sig
  type t =
    { approve_builder_fee : Approve_builder_fee.t
    ; signature : string
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** The user's agent as the server knows it; the reply to [POST /agent/approved] and
    [POST /builder-fee], and part of {!Me}. *)
module Agent_status : sig
  type t =
    { agent_address : Address.t
    ; agent_name : string
    ; approved : bool (** Hyperliquid accepted the [approveAgent] *)
    ; valid_until : Time_ms.t option (** absent when the approval has no expiry *)
    ; builder_fee : string option (** the approved maximum fee rate, e.g. ["0.01%"] *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** [POST /follows], authenticated; the reply is the new {!Follow.t}. Needs an approved
    agent. *)
module Follow_request : sig
  type t =
    { leader : Address.t
    ; scale : Scale_mode.t
    ; caps : Caps.t
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** JSON ["running"], ["paused"], ["stopped"]. *)
module Follow_state : sig
  type t =
    | Running
    | Paused
    | Stopped
  [@@deriving compare, enumerate, equal, sexp, yojson]

  val to_string : t -> string
end

(** [GET /follows/<id>] *)
module Follow : sig
  type t =
    { id : string
    ; leader : Address.t
    ; scale : Scale_mode.t
    ; caps : Caps.t
    ; state : Follow_state.t
    ; created_at : Time_ms.t
    ; pnl : float (** USD attributed to this follow since it started *)
    ; positions : Position.t list (** the follower's positions this follow opened *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** [PATCH /follows/<id>]: pause ([Paused]) or resume ([Running]); the reply is the
    updated {!Follow.t}. [DELETE /follows/<id>] stops a follow for good. *)
module Follow_update : sig
  type t = { state : Follow_state.t } [@@deriving compare, equal, sexp, yojson]
end

(** [GET /me], authenticated: the user's account, agent and follows. *)
module Me : sig
  type t =
    { address : Address.t
    ; account_value : float
    ; total_pnl : float
    ; agent : Agent_status.t option (** absent until an agent is generated *)
    ; follows : Follow.t list
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** Messages pushed on [GET /ws?token=<token>], one JSON object per text frame:

    - [{"type": "me", "me": <Me>}]: on connect and every status interval;
    - [{"type": "follow", "follow": <Follow>}]: when a follow changes;
    - [{"type": "fill", "fill": <Fill>}]: each new fill of the user's account;
    - [{"type": "error", "error": "..."}]. *)
module Ws_push : sig
  type t =
    | Me of Me.t
    | Follow of Follow.t
    | Fill of Fill.t
    | Error of string
  [@@deriving compare, equal, sexp, yojson]

  val to_string : t -> string

  (** Raises like [t_of_yojson] on a malformed or unknown message. *)
  val of_string : string -> t
end

(** The body of every non-2xx reply. *)
module Api_error : sig
  type t = { error : string } [@@deriving compare, equal, sexp, yojson]
end

(** Request paths, relative to the API base URL. Everything but [leaders], [leader] and
    the two [auth_] paths needs [Authorization: Bearer <Auth.Session.token>]. *)
module Endpoint : sig
  (** GET *)
  val leaders : string

  (** GET *)
  val leader : Address.t -> string

  (** POST *)
  val auth_challenge : string

  (** POST *)
  val auth_verify : string

  (** POST *)
  val agent_new : string

  (** POST *)
  val agent_approved : string

  (** POST *)
  val builder_fee : string

  (** POST *)
  val follows : string

  (** GET, PATCH, DELETE *)
  val follow : id:string -> string

  (** GET *)
  val me : string
end
