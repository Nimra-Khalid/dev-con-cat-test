Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "http://localhost:3001",
            "http://127.0.0.1:3001",
            "http://localhost:3002",
            "http://127.0.0.1:3002",
            "http://localhost:3003",
            "http://127.0.0.1:3003",
            "http://localhost:60715",
            "http://192.168.18.113:60715"

    resource "*",
             headers: :any,
             methods: [:get, :post, :options],
             expose: [],
             max_age: 600
  end
end