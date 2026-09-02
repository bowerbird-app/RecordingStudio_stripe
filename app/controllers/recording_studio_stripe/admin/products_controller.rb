# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    class ProductsController < BaseController
      def new
        @kind = params[:kind].presence_in(Product::KINDS) || "plan"
      end

      def create
        product = CreateProduct.call(
          name: params.require(:name),
          kind: params.require(:kind),
          description: params[:description]
        )
        redirect_to admin_screen_url("products"), notice: "#{product.name} is on the catalogue."
      rescue InvalidPrice, ActiveRecord::RecordInvalid => e
        flash.now[:alert] = e.message
        @kind = params[:kind]
        render :new, status: :unprocessable_entity
      end
    end
  end
end
