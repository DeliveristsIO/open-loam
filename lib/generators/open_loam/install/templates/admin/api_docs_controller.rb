module Admin
  # A server-rendered OpenAPI explorer for the app's JSON API (OpenLoam::OpenApi) —
  # manager-only. HTML lists the endpoints, their auth, params, and schemas; the
  # `.json` format serves the raw OpenAPI 3.1 document for tooling. No external
  # JS / Swagger-UI (CSP-safe): the explorer is plain server-rendered HTML.
  class ApiDocsController < BaseController
    before_action { require_role!(:manager) }

    def index
      @doc = OpenLoam::OpenApi.document
      respond_to do |format|
        format.html
        format.json { render json: @doc }
      end
    end
  end
end
