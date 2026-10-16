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

module Equity_point : sig
  type t =
    { time : Time_ms.t
    ; equity : float (** USD account value *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** leader-scoring's view of a leader (metrics, a transparent composite score, a learned
    forecast, capacity and alerts), as hl-leaderboard computes it. Optional numbers are
    [None] (JSON [null]) where a metric is undefined for the leader. *)
module Scoring : sig
  (** One metric. [unit] is ["ratio"] (show as a percentage), ["number"], ["count"],
      ["days"], ["hours"], ["per_day"] or ["multiple"]; [better] is ["higher"], ["lower"]
      or ["neither"]. *)
  module Metric : sig
    type t =
      { name : string
      ; label : string
      ; value : float option
      ; unit : string
      ; better : string
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** One weighted part of the composite score. *)
  module Component : sig
    type t =
      { metric : string
      ; label : string
      ; value : float option
      ; percentile : float (** [0.] to [1.], higher is better after flipping *)
      ; weight : float (** weights sum to 1 *)
      ; contribution : float (** points of the 0 to 100 score *)
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** The estimated cost of copying every leader order at one follower size. *)
  module Capacity_point : sig
    type t =
      { follower_equity : float (** USD *)
      ; orders : int
      ; mean_cost_bps : float (** notional-weighted *)
      ; median_cost_bps : float
      ; p90_cost_bps : float
      ; unfilled_share : float (** share of notional the books could not fill *)
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  module Capacity : sig
    type t =
      { max_cost_bps : float (** the cost that defines capacity *)
      ; capacity_usd : float option (** largest follower equity within [max_cost_bps] *)
      ; curve : Capacity_point.t list
      ; coins_without_book : string list
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** A behaviour change. [kind]: ["drawdown_breach"], ["leverage_spike"],
      ["style_drift"], ["frequency_change"], ["liquidation"]; [severity]: ["info"],
      ["warning"], ["critical"]. *)
  module Alert : sig
    type t =
      { kind : string
      ; severity : string
      ; time : Time_ms.t
      ; message : string
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** What a leaderboard row carries. *)
  module Summary : sig
    type t =
      { score : float (** composite, [0.] to [100.] *)
      ; rank : int option (** among eligible leaders *)
      ; percentile : float option
      ; eligible : bool
      ; predicted_forward_sharpe : float option
      ; capacity_usd : float option
      ; alerts : int
      ; worst_alert : string option
      ; sharpe : float option
      ; max_drawdown : float option
      ; leverage_p95 : float option
      ; integrity_flags : string list
      (** {!Integrity_flag.t} kinds; absent when there are none *)
      ; excluded : bool (** an integrity flag took the leader out of the ranking *)
      ; persistence_percentile : float option
      (** the leader's mean formation percentile over the persistence windows *)
      ; psr : float option (** probabilistic Sharpe ratio *)
      ; dsr : float option (** deflated Sharpe ratio, the leaders being the trials *)
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** A sign that a leader is manipulated or cannot be copied. [kind]: ["self_trade"],
      ["wash_trade"], ["counterparty"], ["co_trading"], ["front_running"],
      ["creation_burst"], ["off_book_price"]; [severity] as for {!Alert}; [accounts]: the
      other accounts involved (a cluster or a counterparty group), absent when none. *)
  module Integrity_flag : sig
    type t =
      { kind : string
      ; severity : string
      ; message : string
      ; accounts : string list
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  module Persistence_point : sig
    type t =
      { time : Time_ms.t (** start of the formation window *)
      ; percentile : float (** [0.] to [1.], 1 is the best *)
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** Where the leader stood in each ranking window, and whether rankings persist at all
      in this universe. *)
  module Persistence : sig
    type t =
      { windows : int
      ; mean_percentile : float option
      ; top_quantile_windows : int
      ; percentiles : Persistence_point.t list
      ; universe_persistent : bool
      ; universe_rank_correlation : float option
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** Selection-bias statistics of the leader's returns (backtest-stats). [dsr] treats
      every scored leader as a trial; [pbo] and [spa_p_value] are the universe's. *)
  module Stats : sig
    type t =
      { periods : int
      ; periods_per_year : float
      ; sharpe_annualized : float option
      ; psr : float option
      ; dsr : float option
      ; min_track_record_periods : float option
      ; pbo : float option
      ; spa_p_value : float option
      ; accepted : bool option (** the statistical gate's verdict *)
      ; reasons : string list (** why the gate rejects *)
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** The universe-level honesty checks behind the ranking: does the ranking persist from
      one window to the next (rank correlation with its interval, decay, transition shares
      between quintiles, the top [top_k] against random picks), the selection statistics,
      and how many leaders the integrity checks flagged and excluded. *)
  module Universe : sig
    type t =
      { persistent : bool
      ; fading : bool
      ; formation : string
      ; window_days : float option
      ; periods : int
      ; rank_correlation : float option
      ; rank_correlation_lower : float option
      ; rank_correlation_upper : float option
      ; top_stays_top_half : float option
      ; decay : float option list (** mean rank correlation 1, 2, ... windows ahead *)
      ; transition : float list list
      (** row [i]: shares of formation quintile [i] (bottom first) in each outcome quintile *)
      ; top_k : int option
      ; top_k_return : float option
      ; random_mean : float option
      ; baseline_percentile : float option
      ; baseline_p_value : float option
      ; leaders_with_stats : int
      ; trials : int option
      ; pbo : float option
      ; spa_p_value : float option
      ; accepted : int
      ; flagged : int
      ; excluded : int
      }
    [@@deriving compare, equal, sexp, yojson]
  end

  (** What a leader page shows. *)
  module Detail : sig
    type t =
      { score : float
      ; rank : int option
      ; percentile : float option
      ; eligible : bool
      ; reasons : string list (** why a leader is not ranked *)
      ; components : Component.t list
      ; predicted_forward_sharpe : float option
      (** the learned model's forecast of the next 30 days' Sharpe ratio *)
      ; metrics : Metric.t list
      ; equity_source : string (** ["venue"], ["anchored"], ["given"] or ["assumed"] *)
      ; bar_seconds : float (** the return period the metrics use *)
      ; equity_curve : Equity_point.t list (** the series the metrics use, oldest first *)
      ; capacity : Capacity.t option (** absent without order books *)
      ; alerts : Alert.t list (** oldest first *)
      ; persistence : Persistence.t option (** absent before the universe checks ran *)
      ; stats : Stats.t option
      ; integrity : Integrity_flag.t list (** absent when there are none *)
      }
    [@@deriving compare, equal, sexp, yojson]
  end
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
    ; scoring : Scoring.Summary.t option (** absent before hl-leaderboard scores it *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** [GET /leaders] *)
module Leaders_response : sig
  type t =
    { as_of : Time_ms.t
    ; leaders : Leader.t list (** sorted by [rank] *)
    ; universe : Scoring.Universe.t option (** absent before the universe checks ran *)
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
    ; scoring : Scoring.Detail.t option (** absent before hl-leaderboard scores it *)
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
    ; algo : string option
    (** how the engine executes the copy orders, in execution-algos' short form:
        ["immediate"] (the default when absent), ["twap:60s:6"], ["passive:30s"],
        ["adaptive:20s"], ...; the server rejects anything it cannot parse *)
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

(** One parent order the engine finished, from its [/status]. [shortfall_bps] is the
    cost against the price when the order was planned, fees included. *)
module Execution_report : sig
  type t =
    { time : Time_ms.t option
    ; algo : string
    ; outcome : string (** ["filled"], ["partial"], ["cancelled"], ... *)
    ; side : Side.t
    ; target : float
    ; filled : float
    ; avg_px : float
    ; arrival_px : float
    ; children : int
    ; fees : float
    ; arrival_slippage_bps : float
    ; shortfall_bps : float
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** The engine's execution totals for one follow. *)
module Execution : sig
  type t =
    { algo : string
    ; parents : int
    ; filled_parents : int
    ; fill_rate : float (** filled over target notional *)
    ; shortfall_bps : float
    ; slippage_bps : float
    ; fees : float (** USD *)
    ; active : int (** parents being worked *)
    ; recent : Execution_report.t list (** newest first *)
    }
  [@@deriving compare, equal, sexp, yojson]
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
    ; algo : string option (** absent for ["immediate"] *)
    ; execution : Execution.t option (** absent until the engine reports it *)
    }
  [@@deriving compare, equal, sexp, yojson]
end

(** [PATCH /follows/<id>]: pause ([Paused]) or resume ([Running]) and/or change the
    execution algorithm (["immediate"] goes back to the default); the reply is the
    updated {!Follow.t}. [DELETE /follows/<id>] stops a follow for good. *)
module Follow_update : sig
  type t =
    { state : Follow_state.t option
    ; algo : string option
    }
  [@@deriving compare, equal, sexp, yojson]
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
