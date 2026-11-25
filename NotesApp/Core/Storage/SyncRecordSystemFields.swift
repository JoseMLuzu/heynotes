import CloudKit

/// Preserves CloudKit's identity/change tag without archiving user fields or file URLs.
/// SyncStateStore supplies persistence/account scoping; this codec has no account access.
enum SyncRecordSystemFields {
    static func encode(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decode(_ data: Data, expecting id: CKRecord.ID, type: String) throws -> CKRecord {
        guard !data.isEmpty, data.count <= 1_048_576 else { throw SyncCloudError.invalidSystemFields }
        do {
            let coder = try NSKeyedUnarchiver(forReadingFrom: data)
            coder.requiresSecureCoding = true
            coder.decodingFailurePolicy = .setErrorAndReturn
            defer { coder.finishDecoding() }
            guard let record = CKRecord(coder: coder), coder.error == nil,
                  record.recordID == id, record.recordType == type, record.allKeys().isEmpty else {
                throw SyncCloudError.invalidSystemFields
            }
            return record
        } catch { throw SyncCloudError.invalidSystemFields }
    }
}
