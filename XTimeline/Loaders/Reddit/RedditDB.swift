//
//  RedditDB.swift
//  XTimeline
//
//  Created by ZhangChen on 2021/12/30.
//  Copyright © 2021 ZhangChen. All rights reserved.
//

import Foundation
import SQLite3

class DBWrapper {
    typealias DBHandle = OpaquePointer?
    typealias Statement = OpaquePointer?

    var dbHandle: DBHandle = DBHandle(nilLiteral: ())
    var q : DispatchQueue = DispatchQueue(label: "dbq")
    
    var queryStmt1 = Statement(nilLiteral: ())
    var queryStmt2 = Statement(nilLiteral: ())
    var saveStmt = Statement(nilLiteral: ())

    init(external: Bool) throws {
        //self.subreddit = subreddit
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!.appending("/reddit/")
        let dbFilename = (external ? path + ".external/" : path) + "/cache.db"
        try dbFilename.withCString { (pFilename) in
            guard sqlite3_open(pFilename, &dbHandle) == SQLITE_OK else {
                throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed opening cache.db"])
            }
        }
        
        let initSql = "CREATE TABLE IF NOT EXISTS rdt_child_data (url text, hash text, sub text, post_id text UNIQUE);"
        
        try initSql.withCString { (initCStr) in
            var statement = Statement(nilLiteral: ())
            guard sqlite3_prepare_v2(dbHandle, initCStr, Int32(initSql.lengthOfBytes(using: .utf8)), &statement, nil) == SQLITE_OK else {
                throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare initSql"])
            }
            guard sqlite3_step(statement) == SQLITE_DONE && sqlite3_finalize(statement) == SQLITE_OK else {
                throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed exec initSql"])
            }
        }
        
        let indexSql = "CREATE INDEX IF NOT EXISTS rdt_sub_post ON rdt_child_data (sub, post_id);"
        try indexSql.withCString { (initCStr) in
            var statement = Statement(nilLiteral: ())
            guard sqlite3_prepare_v2(dbHandle, initCStr, Int32(indexSql.lengthOfBytes(using: .utf8)), &statement, nil) == SQLITE_OK else {
                throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare indexSql"])
            }
            guard sqlite3_step(statement) == SQLITE_DONE && sqlite3_finalize(statement) == SQLITE_OK else {
                throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed exec indexSql"])
            }
        }
        
        let query1 = "SELECT hash FROM rdt_child_data WHERE post_id = ? AND sub = ?;"
        try query1.withCString({ (cstr) in
            guard sqlite3_prepare_v2(dbHandle, cstr, Int32(query1.lengthOfBytes(using: .utf8)), &self.queryStmt1, nil) == SQLITE_OK else {
                throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare query1"])
            }
        })
        let query2 = "SELECT hash FROM rdt_child_data WHERE url = ?;"
        try query2.withCString({ (cstr) in
            guard sqlite3_prepare_v2(dbHandle, cstr, Int32(query2.lengthOfBytes(using: .utf8)), &self.queryStmt2, nil) == SQLITE_OK else {
                throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare query2"])
            }
        })
        
        let save = "INSERT OR REPLACE INTO rdt_child_data (sub, url, post_id, hash) VALUES (?, ?, ?, ?);"
        try save.withCString({ (cstr) in
            guard sqlite3_prepare_v2(dbHandle, cstr, Int32(save.lengthOfBytes(using: .utf8)), &self.saveStmt, nil) == SQLITE_OK else {
                throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare savestmt"])
            }
        })
    }
    func query(sub: String, post: String, completion: @escaping (String?) -> () ) {
        q.async {
            let result = post.withCString { (postStr) -> String? in
                sub.withCString { (subStr) -> String? in
                    guard sqlite3_bind_text(self.queryStmt1, 1, subStr, Int32(sub.utf8.count), nil) == SQLITE_OK
                        && sqlite3_bind_text(self.queryStmt1, 2, postStr, Int32(post.utf8.count), nil) == SQLITE_OK else {
                            return nil
                    }
                    switch sqlite3_step(self.queryStmt1) {
                    case SQLITE_ROW:
                        return String(cString: sqlite3_column_text(self.queryStmt1, 0))
                    default:
                        break
                    }
                    return nil
                }
            }
            sqlite3_reset(self.queryStmt1)
            completion(result)
        }
    }
    func query(url: String, completion: @escaping (String?) -> () ) {
        q.async {
            let result = url.withCString { (urlStr) -> String? in
                guard sqlite3_bind_text(self.queryStmt2, 1, urlStr, Int32(url.utf8.count), nil) == SQLITE_OK else {
                    return nil
                }
                switch sqlite3_step(self.queryStmt2) {
                case SQLITE_ROW:
                    return String(cString: sqlite3_column_text(self.queryStmt2, 0))
                default:
                    break
                }
                return nil
            }
            sqlite3_reset(self.queryStmt2)
            completion(result)
        }
    }
    
    func queryBatch(sub: String, after: String = "", count: Int) -> [(String, String)] /*[(post_id, hash)]*/ {
        var result :[(String, String)] = []
        let query1 = after == "" ? "SELECT post_id, MIN(hash) FROM rdt_child_data WHERE sub = ?1 GROUP BY post_id ORDER BY post_id DESC LIMIT ?2;" : "SELECT post_id, MIN(hash) FROM rdt_child_data WHERE sub = ?1 AND post_id < ?2 GROUP BY post_id ORDER BY post_id DESC LIMIT ?3;"
        q.sync {
            try? query1.withCString({ (cstr) in
            
                var stmt = Statement(nilLiteral: ())
                guard sqlite3_prepare_v2(dbHandle, cstr, Int32(query1.lengthOfBytes(using: .utf8)), &stmt, nil) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed preparing query1"])
                }
                
                guard after.withCString({ (afterStr) -> Bool in
                    guard sub.withCString({(subStr) -> Bool in
                        let r1 = sqlite3_bind_text(stmt, 1, subStr, Int32(strlen(subStr)), nil)
                        if after == "" {
//                                let r2 = sqlite3_bind_text(stmt, 2, afterStr, Int32(strlen(afterStr)), nil)
                            let r3 = sqlite3_bind_int(stmt, 2, Int32(count))
                            guard  (r1 == SQLITE_OK) && (r3 == SQLITE_OK) else {
                                return false
                            }
                        } else {
                            let r2 = sqlite3_bind_text(stmt, 2, afterStr, Int32(strlen(afterStr)), nil)
                            let r3 = sqlite3_bind_int(stmt, 3, Int32(count))
                            guard  (r1 == SQLITE_OK) && (r2 == SQLITE_OK) && (r3 == SQLITE_OK) else {
                                return false
                            }
                        }
                        
                        var r : Int32
                        r = sqlite3_step(stmt)
                        while (r == SQLITE_ROW) {
                            if let pIdStr = sqlite3_column_text(stmt, 0),
                                let hashStr = sqlite3_column_text(stmt, 1) {
                                let pId = String(cString: pIdStr)
                                let hash = String(cString: hashStr)
                                result.append((pId, hash))
                            }
                            r = sqlite3_step(stmt)
                        }
                        
                        return true
                    }) else {return false}
                    return true
                }) else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed binding query1"])
                }
                _ = sqlite3_finalize(stmt)
            })
        }
        return result
    }
    func save(sub: String, url: String, postId: String, hash: String) {
        q.async {
            
            url.withCString { (urlStr) in
                postId.withCString { (postStr) in
                    sub.withCString { (subStr) in
                        hash.withCString { (hashStr) in
                            guard sqlite3_bind_text(self.saveStmt, 1, subStr, Int32(sub.utf8.count), nil) == SQLITE_OK else {
                                return
                            }
                            guard sqlite3_bind_text(self.saveStmt, 2, urlStr, Int32(url.utf8.count), nil) == SQLITE_OK else {
                                return
                            }
                            guard sqlite3_bind_text(self.saveStmt, 3, postStr, Int32(postId.utf8.count), nil) == SQLITE_OK else {
                                return
                            }
                            guard sqlite3_bind_text(self.saveStmt, 4, hashStr, Int32(hash.utf8.count), nil) == SQLITE_OK else {
                                return
                            }
//                                guard sqlite3_bind_text(self.saveStmt, 5, postStr, Int32(postId.utf8.count), nil) == SQLITE_OK else {
//                                    return
//                                }
                            sqlite3_step(self.saveStmt)
                        }
                    }
                }
            }
            sqlite3_reset(self.saveStmt)
        }
    }
    deinit {
        q.sync {
            sqlite3_finalize(queryStmt1)
            sqlite3_finalize(queryStmt2)
            sqlite3_close(dbHandle)
        }
    }
}
