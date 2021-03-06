import Foundation

public protocol APIServiceReaderDelegate: class {
    func matchReqest(_ request: URLRequest?, _ interaction: APIServiceContractInteraction) -> Bool
}

extension APIServiceReaderDelegate {
    func matchReqest(_ request: URLRequest?, _ interaction: APIServiceContractInteraction) -> Bool {
        return false
    }
}

open class APIServiceReader {
    
    private weak var output: MonorailDebugOutput?
    
    open var fileName: String {
        return files.map{ $0.lastPathComponent }.joined(separator: ", ")
    }
    var files: [URL]
    var interactions = [APIServiceContractInteraction]()
    var consumerVariables: [String: Any] = [:]
    internal var providerVariables: [String: Any] = [:]
    internal var notifications = [[String: AnyObject]]()
    weak var readDelegate: APIServiceReaderDelegate?
    
    public init(readDelegate: APIServiceReaderDelegate? = nil, output: MonorailDebugOutput? = nil) {
        self.output = output
        files = []
        self.readDelegate = readDelegate
    }
    
    public init(files: [URL], externalFileRootPath: String? = nil, delegate: APIServiceReaderDelegate? = nil, output: MonorailDebugOutput? = nil) {
        self.output = output
        self.files = files
        
        guard files.count > 0 else {
            output?.log("Empty file list.")
            return
        }
        
        for file in files {
            guard let data = try? Data(contentsOf: file),
                let contractJson = String(data: data, encoding: .utf8) else {
                output?.log("File error:\(file.absoluteString)")
                continue
            }
            
            output?.log("reading: \(file.absoluteString)")
            
            mergeContractJson(contractJson, fileName: file.lastPathComponent, externalFileRootPath: externalFileRootPath ?? file.deletingLastPathComponent().relativePath )
        }
    }
    
    public init(contractJson: String, externalFileRootPath: String? = nil, output: MonorailDebugOutput? = nil) {
        self.output = output
        files = []
        mergeContractJson(contractJson, externalFileRootPath: externalFileRootPath)
    }
    
    func mergeContractJson(_ contractJson: String, fileName: String? = nil, externalFileRootPath: String? = nil) {
        guard let data = contractJson.data(using: String.Encoding.utf8), let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            output?.log("Json parsing error, file name:\(fileName ?? "nil")")
            return
        }
        
        if let newConsumerVariables = json?[apiServiceConsumerKey] as? [String: Any] {
            
            let newConsumerVariablesUnwrapFileRef = newConsumerVariables.loadFileRef(externalFileRootPath: externalFileRootPath)
            
            consumerVariables.merge(newConsumerVariablesUnwrapFileRef) { (_, newValue) in newValue }
            
            if let notifications = consumerVariables[apiServiceConsumerNotificationsKey] as? [[String: AnyObject]] {
                self.notifications.append(contentsOf: notifications)
            }
        }
        
        if let newProviderVariables = json?[apiServiceProviderKey] as? [String: Any] {
            providerVariables.merge(newProviderVariables) { (_, newValue) in newValue }
        }
        
        guard let interactionsJson = json?[apiServiceInteractionsKey] as? [[String: Any]] else {
            return
        }
        
        let baseUrl = getConsumerVariables(key: apiServiceBaseUrlKey) as? String
        
        for interactionJosn in interactionsJson {
            let interaction: APIServiceContractInteraction
            if let idRef = interactionJosn[APIServiceContractInteraction.idRefKey] as? String {
                if let interactionTemplate = interactions.filter({ $0.id == idRef }).first  {
                    interaction = APIServiceContractInteraction(template: interactionTemplate)
                    interaction.loadJson(interactionJosn, externalFileRootPath: externalFileRootPath)
                } else {
                    output?.log("Invalidate idReference: \(idRef)")
                    interaction = APIServiceContractInteraction(json: interactionJosn, baseUrl: baseUrl, fileName: fileName, externalFileRootPath: externalFileRootPath)
                }
            } else {
                interaction = APIServiceContractInteraction(json: interactionJosn, baseUrl: baseUrl, fileName: fileName, externalFileRootPath: externalFileRootPath)
            }
            
            interactions.append(interaction)
        }
    }
    
    func getProviderVariable(key: String) -> Any? {
        return providerVariables[key]
    }
    
    func getConsumerVariables(key: String) -> Any? {
        return consumerVariables[key]
    }
    
    func getResponse(for request: URLRequest?) -> APIServiceContractInteraction? {
        guard let request = request else {
            return nil
        }
        
        output?.log("Searching response in: \(fileName)")
        
        let matchedInteractions = interactions.filter({ (readDelegate?.matchReqest(request, $0) ?? false) || $0.matchReqest(request) })
        let bestMatch = matchedInteractions.filter({ !$0.consumed }).first ?? matchedInteractions.last
        bestMatch?.consumed = true
        
        if let bestMatch = bestMatch {
            output?.log("Found best match id: \(bestMatch.id ?? "nil")")
        } else {
            output?.log("No matching")
        }
        return bestMatch
    }
    
    func getResponseObject(for request: URLRequest?) ->  (HTTPURLResponse, Data?, Error?)? {
        return getResponse(for: request)?.responseObjects()
    }
    
    func getInteractionBy(id: String) -> APIServiceContractInteraction? {
        return interactions.first(where: { $0.id == id })
    }
    
    func resetInteractionsConsumedFlag() {
        for interaction in interactions {
            interaction.consumed = false
        }
    }
}
