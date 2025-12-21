require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name string' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'sets @name to the given value' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) { nil }
      let(:user) { described_class.new(name) }

      it 'sets @name to nil without raising' do
        expect { described_class.new(name) }.not_to raise_error
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Bob') }
    let(:db) { double('DB') }

    before do
      stub_const('DB', db)
      allow(db).to receive(:execute).and_return(:db_result)
    end

    context 'with numeric id' do
      let(:id) { 42 }

      it 'queries the DB with the id and returns the DB result' do
        result = user.find_user(id)
        expect(result).to eq(:db_result)
        expect(db).to have_received(:execute).with('SELECT * FROM users WHERE id = 42')
      end
    end

    context 'with a string id containing SQL' do
      let(:id) { '1 OR 1=1' }

      it 'passes the id directly into the query string' do
        user.find_user(id)
        expect(db).to have_received(:execute).with('SELECT * FROM users WHERE id = 1 OR 1=1')
      end
    end

    context 'with nil id' do
      let(:id) { nil }

      it 'builds the query with a blank id' do
        user.find_user(id)
        expect(db).to have_received(:execute).with('SELECT * FROM users WHERE id = ')
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 5 }

      before do
        allow(db).to receive(:execute).and_raise(StandardError, 'DB down')
      end

      it 'bubbles up the error' do
        expect { user.find_user(id) }.to raise_error(StandardError, 'DB down')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Charlie') }

    it 'returns 6' do
      expect(user.bad_method).to eq(6)
    end
  end
end
