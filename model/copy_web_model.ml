(** Pure logic behind the web app's pages: routing, formatting, table sorting, chart
    geometry and form validation. Nothing here touches the DOM, so it is tested natively. *)

module Route = Route
module Format = Format
module Leader_table = Leader_table
module Chart = Chart
module Follow_form = Follow_form
module Mock_state = Mock_state
module Agent_check = Agent_check
module Scoring_view = Scoring_view
