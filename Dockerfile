FROM ruby:3.2-slim

RUN apt-get update -qq && apt-get install -y \
build-essential \
libpq-dev \
libyaml-dev \
libsqlite3-dev \
nodejs \
npm \
git \
&& npm install -g yarn \
&& rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile ./
# to install "pg" gem
COPY config/database.yml ./config/database.yml
RUN bundle install

COPY package.json yarn.lock ./
RUN yarn install

COPY . .

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]