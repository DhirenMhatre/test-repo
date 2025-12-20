require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    let(:name) { 'Alice' }

    it 'stores the provided name in @name' do
      user = described_class.new(name)
      expect(user.instance_variable_get(:@name)).to eq(name)
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'stores nil in @name' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Alice') }
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with an integer id' do
      let(:id) { 42 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'executes the SQL and returns the result' do
        expect(db_double).to receive(:execute).with(expected_query).and_return(['row'])
        result = user.find_user(id)
        expect(result).to eq(['row'])
      end
    end

    context 'with a string id containing potentially unsafe input' do
      let(:id) { '1; DROP TABLE users;' }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'passes the interpolated string directly to DB.execute' do
        expect(db_double).to receive(:execute).with(expected_query).and_return(['row'])
        result = user.find_user(id)
        expect(result).to eq(['row'])
      end
    end

    context 'with nil id' do
      let(:id) { nil }
      let(:expected_query) { 'SELECT * FROM users WHERE id = ' }

      it 'executes a query with an empty id value' do
        expect(db_double).to receive(:execute).with(expected_query).and_return([])
        result = user.find_user(id)
        expect(result).to eq([])
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 1 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'propagates the error' do
        expect(db_double).to receive(:execute).with(expected_query).and_raise(StandardError.new('DB error'))
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Bob') }

    it 'returns 6' do
      expect(user.bad_method).to eq(6)
    end
  end
end
