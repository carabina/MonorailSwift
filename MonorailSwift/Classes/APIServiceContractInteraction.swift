import Foundation

private let fileRefKey = "fileReference"

open class APIServiceContractInteraction {
    private let requestKey = "request"
    private let responseKey = "response"
    private let headersKey = "headers"
    private let bodyKey = "body"
    private let dataKey = "data"
    private let methodKey = "method"
    private let pathKey = "path"
    
    private let responseStatusKey = "status"
    private let idKey = "id"
    static let idRefKey = "idReference"
    
    private(set) var request: [String: Any] = [:]
    private(set) var response: [String: Any] = [:]
    
    var baseUrl: String?
    var path: String?
    var method: String?
    
    var fileName: String?
    var id: String?
    
    private(set) var consumerVariables: [String: Any] = [:]
    private(set) var providerVariables: [String: Any] = [:]
    
    // temp variables
    var consumed = false
    
    func saveProviderVariable(key: String, value: Any) {
        providerVariables[key] = value
    }
    
    func getProviderVariable(key: String) -> Any? {
        return providerVariables[key]
    }
    
    func saveConsumerVariables(key: String, value: Any) {
        consumerVariables[key] = value
    }
    
    func getConsumerVariables(key: String) -> Any? {
        return consumerVariables[key]
    }
    
    init(template: APIServiceContractInteraction) {
        self.request = template.request
        self.response = template.response
        self.baseUrl = template.baseUrl
        self.path = template.path
        self.method = template.method
        self.fileName = template.fileName
        self.id = template.id
        self.consumerVariables = template.consumerVariables
        self.providerVariables = template.providerVariables
    }
    
    init(json: [String: Any], baseUrl: String? = nil, fileName: String? = nil, externalFileRootPath: String? = nil) {
        self.baseUrl = baseUrl
        self.fileName = fileName
        
        loadJson(json, externalFileRootPath: externalFileRootPath)
    }
    
    func loadJson(_ json: [String: Any], externalFileRootPath: String? = nil) {
        
        if let externalFilePath = json[fileRefKey] as? String,
            let externalJson = loadJsonFromFile(externalFilePath, externalFileRootPath: externalFileRootPath) {
            loadJson(externalJson, externalFileRootPath: externalFileRootPath)
        }
        
        loadRequestJson(json[requestKey] as? [String: Any])
        loadResponseJson(json[responseKey] as? [String: Any], externalFileRootPath: externalFileRootPath)
        
        if let consumerVariables = json[apiServiceConsumerKey] as? [String: Any] {
            self.consumerVariables.deepMerge(consumerVariables)
        }
        
        if let providerVariables = json[apiServiceProviderKey] as? [String: Any] {
            self.providerVariables.deepMerge(providerVariables)
        }
        
        if let idString = json[idKey] as? String {
            self.id = idString
        }
    }
    
    init(request: URLRequest?, uploadData: Data? = nil, response: URLResponse?, data: Data? = nil, baseUrl: String? = nil) {
        self.baseUrl = baseUrl
        guard let request = request, let url = request.url?.absoluteString, let response = response as? HTTPURLResponse else {
            return
        }
        
        setRequest(method: request.httpMethod ?? "GET", path: url, headers: request.allHTTPHeaderFields, body: request.httpBody, uploadData: uploadData)
        
        setRespondWith(status: response.statusCode, headers: response.allHeaderFields as? [String: Any], body: data)
    }

    var requestHeader: [String: Any]? {
        return request[headersKey] as? [String: Any]
    }
    
    var requestBody: [String: Any]? {
        return request[bodyKey] as? [String: Any]
    }
    var responseBody: [String: Any]? {
        return response[bodyKey] as? [String: Any]
    }
    
    var responseHeader: [String: Any]? {
        return response[headersKey] as? [String: Any]
    }

    private func loadRequestJson(_ json: [String: Any]?) {
        if let request = json {
            self.request.deepMerge(request)
            path = request[pathKey] as? String
            if let baseUrl = baseUrl, let path = path, path.hasPrefix(baseUrl) {
                self.path = String(path[baseUrl.endIndex...])
                self.request[pathKey] = path
            }
            method = request[methodKey] as? String
        }
    }
    
    private func loadResponseJson(_ json: [String: Any]?, externalFileRootPath: String? = nil) {
        guard let json = json else {
            return
        }
        
        if let externalFilePath = json[fileRefKey] as? String,
            let externalJson = loadJsonFromFile(externalFilePath, externalFileRootPath: externalFileRootPath) {
            response.deepMerge(externalJson)
        }
            
        response.deepMerge(json)
    }
    
    func matchReqest(_ urlRequest: URLRequest) -> Bool {
        guard let method = method, let path = path, let requestUrl = urlRequest.url?.absoluteString else {
            return false
        }
        
        return method == urlRequest.httpMethod && requestUrl.hasSuffix(path)
    }
    
    func matchReqest(_ method: String?, path: String?) -> Bool {
        guard let path = path, let pactPath = self.path else {
            return false
        }
        
        return method == self.method && path.hasSuffix(pactPath)
    }
    
    func responseObjects() -> (HTTPURLResponse, Data?, Error?)? {
        guard let path = path, let url = URL(string: path), let statusCode = response[responseStatusKey] as? Int else {
            return nil
        }
        
        guard let httpURLResponse = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: response[headersKey] as? [String: String]) else {
            return nil
        }
        
        let jsonObject = response[bodyKey] as? [String: Any]
        var data: Data? = nil
        do {
            if let jsonObject = jsonObject {
                data = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            }
        } catch {
            data = nil
        }
        
        if data == nil {
            data = (response[dataKey] as? String)?.fromBase64ToData()
        }
        
        return (httpURLResponse, data, nil)
    }
    
    private func setRequest(method: String,
                            path: String,
                            headers: [String: String]? = nil,
                            body: Data? = nil,
                            uploadData: Data? = nil) {
        var requestJson: [String: Any] = [methodKey: method, pathKey: path]
        if let headersValue = headers, !headersValue.isEmpty {
            requestJson[headersKey] = headersValue
        }
        if let bodyValue = body {
            do {
                let json = try JSONSerialization.jsonObject(with: bodyValue, options: .mutableContainers)
                requestJson[bodyKey] = json
            } catch {
                requestJson[bodyKey] = bodyValue.base64EncodedString()
            }
        }
        
        if let uploadData = uploadData {
            requestJson[dataKey] = uploadData.base64EncodedString()
        }
        
        loadRequestJson(requestJson)
    }
    
    private func setRespondWith(status: Int,
                                headers: [String: Any]? = nil,
                                body: Data? = nil) {
        response = [responseStatusKey: status]
        if let headersValue = headers {
            response[headersKey] = headersValue
        }
        
        if let bodyValue = body {
            do {
                let json = try JSONSerialization.jsonObject(with: bodyValue, options: .mutableContainers)
                response[bodyKey] = json
            } catch {
                response[dataKey] = bodyValue.base64EncodedString()
            }
        }
    }
    
    func payload() -> [String: Any] {
        var payload: [String: Any] = [requestKey: request, responseKey: response]
        
        if let id = id {
            payload[idKey] = id
        }
        
        if !consumerVariables.isEmpty {
            payload[apiServiceConsumerKey] = consumerVariables
        }
        
        if !providerVariables.isEmpty {
            payload[apiServiceProviderKey] = providerVariables
        }
        
        return payload
    }
}

private func loadJsonFromFile(_ filePath: String?, externalFileRootPath: String? = nil) -> [String: Any]? {
    if let filePath = filePath,
        let externalFileRootPath = externalFileRootPath,
        let data = try? Data(contentsOf: URL(fileURLWithPath: externalFileRootPath).appendingPathComponent(filePath)),
        let externalJson = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
        return externalJson
    }
    
    return nil
}

extension Dictionary {
    mutating func deepMerge(_ dict: Dictionary) {
        merge(dict) { (current, new) in
            if var currentDict = current as? Dictionary, let newDict = new as? Dictionary {
                currentDict.deepMerge(newDict)
                return current
            }
            return new
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func loadFileRef(externalFileRootPath: String? = nil) -> Dictionary {
        if let externalFilePath = self[fileRefKey] as? String,
            var externalJson = loadJsonFromFile(externalFilePath, externalFileRootPath: externalFileRootPath) {
            externalJson.deepMerge(self)
            return externalJson
        }

        return self
    }
}

extension String {
    func fromBase64ToData() -> Data? {
        let rem = self.count % 4
        
        var ending = ""
        if rem > 0 {
            let amount = 4 - rem
            ending = String(repeating: "=", count: amount)
        }
        
        let base64 = self.replacingOccurrences(of: "-", with: "+", options: NSString.CompareOptions(rawValue: 0), range: nil)
            .replacingOccurrences(of: "_", with: "/", options: NSString.CompareOptions(rawValue: 0), range: nil) + ending
        
        return Data(base64Encoded: base64, options: NSData.Base64DecodingOptions(rawValue: 0))
    }
}
