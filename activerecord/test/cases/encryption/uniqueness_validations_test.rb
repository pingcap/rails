# frozen_string_literal: true

require "cases/encryption/helper"
require "models/book_encrypted"
require "models/author_encrypted"

class ActiveRecord::Encryption::UniquenessValidationsTest < ActiveRecord::EncryptionTestCase
  def teardown
    EncryptedBookWithDowncaseName.delete_all
  end

  test "uniqueness validations work" do
    EncryptedBookWithDowncaseName.create!(name: "dune")
    assert_raises ActiveRecord::RecordInvalid do
      EncryptedBookWithDowncaseName.create!(name: "dune")
    end
  end

  test "uniqueness validations work when mixing encrypted an unencrypted data" do
    ActiveRecord::Encryption.config.support_unencrypted_data = true

    ActiveRecord::Encryption.without_encryption { EncryptedBookWithDowncaseName.create! name: "dune" }

    assert_raises ActiveRecord::RecordInvalid do
      EncryptedBookWithDowncaseName.create!(name: "dune")
    end
  end

  test "uniqueness validations work when using old encryption schemes" do
    ActiveRecord::Encryption.config.previous = [ { downcase: true } ]

    OldEncryptionBook = Class.new(UnencryptedBook) do
      self.table_name = "encrypted_books"

      validates :name, uniqueness: true
      encrypts :name, deterministic: true, downcase: false
    end

    OldEncryptionBook.create! name: "dune"

    assert_raises ActiveRecord::RecordInvalid do
      OldEncryptionBook.create! name: "DUNE"
    end
  ensure
    OldEncryptionBook.delete_all
  end
end
