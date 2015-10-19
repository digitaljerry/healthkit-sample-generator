//
//  DataExporter.swift
//  Pods
//
//  Created by Michael Seemann on 07.10.15.
//
//

import Foundation
import HealthKit

internal protocol DataExporter {
    var message: String {get}
    func export(healthStore: HKHealthStore, exportTargets: [ExportTarget]) throws -> Void
}

internal class BaseDataExporter {
    var healthQueryError: NSError?  = nil
    var exportError: ErrorType?     = nil
    var exportConfiguration: ExportConfiguration
    let sortDescriptor              = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
    
    internal init(exportConfiguration: ExportConfiguration){
        self.exportConfiguration = exportConfiguration
    }
    
    func rethrowCollectedErrors() throws {
        
        // throw collected errors in the completion block
        if healthQueryError != nil {
            print(healthQueryError)
            throw ExportError.DataWriteError(healthQueryError?.description)
        }
        if let throwableError = exportError {
            throw throwableError
        }
    }
}

internal class MetaDataExporter : BaseDataExporter, DataExporter {
    
    internal var message = "exporting metadata"
    
    internal func export(healthStore: HKHealthStore, exportTargets: [ExportTarget]) throws {
        for exportTarget in exportTargets {
            try exportTarget.writeMetaData(creationDate: NSDate(), profileName: exportConfiguration.profileName, version:"0.2.0")
        }
    }
}

internal class UserDataExporter: BaseDataExporter, DataExporter {
    
    internal var message = "exporting user data"
    
    internal func export(healthStore: HKHealthStore, exportTargets: [ExportTarget]) throws {
        var userData = Dictionary<String, AnyObject>()
        
        if let birthDay = try? healthStore.dateOfBirth() {
            userData["dateOfBirth"] = birthDay
        }
        
        if let sex = try? healthStore.biologicalSex() where sex.biologicalSex != HKBiologicalSex.NotSet {
            userData["biologicalSex"] = sex.biologicalSex.rawValue
        }
        
        if let bloodType = try? healthStore.bloodType() where bloodType.bloodType != HKBloodType.NotSet {
            userData["bloodType"] = bloodType.bloodType.rawValue
        }
        
        if let fitzpatrick = try? healthStore.fitzpatrickSkinType() where fitzpatrick.skinType != HKFitzpatrickSkinType.NotSet {
            userData["fitzpatrickSkinType"] = fitzpatrick.skinType.rawValue
        }
        
        for exportTarget in exportTargets {
            try exportTarget.writeUserData(userData)
        }
    }
}


internal class QuantityTypeDataExporter: BaseDataExporter, DataExporter {
    internal var message:String = ""
    
    var type : HKQuantityType
    var unit: HKUnit
    
    let queryCountLimit = 10000
    
    internal init(exportConfiguration: ExportConfiguration, type: HKQuantityType, unit: HKUnit){
        self.type = type
        self.unit = unit
        self.message = "exporting \(type)"
        super.init(exportConfiguration: exportConfiguration)
    }
    
    func writeResults(results: [HKSample]?, exportTargets: [ExportTarget]) throws -> Void {
        for sample in results as! [HKQuantitySample] {
            
            let value = sample.quantity.doubleValueForUnit(self.unit)
            
            for exportTarget in exportTargets {
                let dict = ["uuid":sample.UUID.UUIDString, "sdate":sample.startDate, "edate":sample.endDate, "value":value]
                try exportTarget.writeDictionary(dict);
            }
        }
    }
    
    func anchorQuery(healthStore: HKHealthStore, exportTargets: [ExportTarget], anchor : HKQueryAnchor?) throws -> (anchor:HKQueryAnchor?, count:Int?) {
        
        let semaphore = dispatch_semaphore_create(0)
        var resultAnchor: HKQueryAnchor?
        var resultCount: Int?
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: exportConfiguration.getPredicate(),
            anchor: anchor ,
            limit: queryCountLimit) { (query, results, deleted, newAnchor, error) -> Void in

            if error != nil {
                self.healthQueryError = error
            } else {
                do {
                    try self.writeResults(results, exportTargets: exportTargets)
                } catch let err {
                    self.exportError = err
                }
            }
            resultAnchor = newAnchor
            resultCount = results?.count
            dispatch_semaphore_signal(semaphore)
        }
        
        healthStore.executeQuery(query)
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        
        try rethrowCollectedErrors()
        
        let result = (anchor:resultAnchor, count: resultCount)
        
        return result
    }
    
    
    internal func export(healthStore: HKHealthStore, exportTargets: [ExportTarget]) throws {
        for exportTarget in exportTargets {
            try exportTarget.startWriteQuantityType(type, unit:unit)
            try exportTarget.startWriteDatas()
        }

        var result : (anchor:HKQueryAnchor?, count:Int?) = (anchor:nil, count: -1)
        repeat {
            result = try anchorQuery(healthStore, exportTargets: exportTargets, anchor:result.anchor)

        } while result.count != 0 || result.count==queryCountLimit

        for exportTarget in exportTargets {
            try exportTarget.endWriteDatas()
            try exportTarget.endWriteType()
        }
     }
}

internal class CategoryTypeDataExporter: BaseDataExporter, DataExporter {
    internal var message:String = ""
    var type : HKCategoryType
    let queryCountLimit = 10000
    
    internal init(exportConfiguration: ExportConfiguration, type: HKCategoryType){
        self.type = type
        self.message = "exporting \(type)"
        super.init(exportConfiguration: exportConfiguration)
    }
    
    func writeResults(results: [HKCategorySample], exportTargets: [ExportTarget]) throws -> Void {
        for sample in results {
            
            for exportTarget in exportTargets {
                let dict = ["uuid":sample.UUID.UUIDString, "sdate":sample.startDate, "edate":sample.endDate, "value":sample.value]
                try exportTarget.writeDictionary(dict);
            }
        }
    }
    
    func anchorQuery(healthStore: HKHealthStore, exportTargets: [ExportTarget], anchor : HKQueryAnchor?) throws -> (anchor:HKQueryAnchor?, count:Int?) {
        
        let semaphore = dispatch_semaphore_create(0)
        var resultAnchor: HKQueryAnchor?
        var resultCount: Int?
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: exportConfiguration.getPredicate(),
            anchor: anchor ,
            limit: queryCountLimit) { (query, results, deleted, newAnchor, error) -> Void in
                
                if error != nil {
                    self.healthQueryError = error
                } else {
                    do {
                        try self.writeResults(results as! [HKCategorySample], exportTargets: exportTargets)
                    } catch let err {
                        self.exportError = err
                    }
                }
                
                resultAnchor = newAnchor
                resultCount = results?.count
                dispatch_semaphore_signal(semaphore)
        }
        
        healthStore.executeQuery(query)
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        
        try rethrowCollectedErrors()
        
        let result = (anchor:resultAnchor, count: resultCount)
        
        return result
    }
    
    
    internal func export(healthStore: HKHealthStore, exportTargets: [ExportTarget]) throws {
        for exportTarget in exportTargets {
            try exportTarget.startWriteType(type)
            try exportTarget.startWriteDatas()
        }
        var result : (anchor:HKQueryAnchor?, count:Int?) = (anchor:nil, count: -1)
        repeat {
            result = try anchorQuery(healthStore, exportTargets: exportTargets, anchor:result.anchor)
        } while result.count != 0 || result.count==queryCountLimit
        
        for exportTarget in exportTargets {
            try exportTarget.endWriteDatas()
            try exportTarget.endWriteType()
        }

    }
}

internal class CorrelationTypeDataExporter: BaseDataExporter, DataExporter {
    internal var message:String = ""
    var type : HKCorrelationType
    let queryCountLimit = 10000
    
    internal init(exportConfiguration: ExportConfiguration, type: HKCorrelationType){
        self.type = type
        self.message = "exporting \(type)"
        super.init(exportConfiguration: exportConfiguration)
    }
    
    
    func anchorQuery(healthStore: HKHealthStore, exportTargets: [ExportTarget], anchor : HKQueryAnchor?) throws -> (anchor:HKQueryAnchor?, count:Int?) {
        
        let semaphore = dispatch_semaphore_create(0)
        var resultAnchor: HKQueryAnchor?
        var resultCount: Int?
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: exportConfiguration.getPredicate(),
            anchor: anchor ,
            limit: queryCountLimit) { (query, results, deleted, newAnchor, error) -> Void in
                
                if error != nil {
                    self.healthQueryError = error
                } else {
                    do {
                        for sample in results as! [HKCorrelation] {
                            
                            var dict = ["uuid":sample.UUID.UUIDString, "sdate":sample.startDate, "edate":sample.endDate]
                            var subSampleArray:[AnyObject] = []

                            for subsample in sample.objects {
                                subSampleArray.append([
                                    "type": subsample.sampleType.identifier,
                                    "uuid": subsample.UUID.UUIDString
                                    ])
                            }
                            
                            dict["objects"] = subSampleArray
                            
                            for exportTarget in exportTargets {
                                try exportTarget.writeDictionary(dict);
                            }

                        }
                    } catch let err {
                        self.exportError = err
                    }
                }
                
                resultAnchor = newAnchor
                resultCount = results?.count
                dispatch_semaphore_signal(semaphore)
        }
        
        healthStore.executeQuery(query)
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        
        try rethrowCollectedErrors()
        
        let result = (anchor:resultAnchor, count: resultCount)
        
        return result
    }
    
    internal func export(healthStore: HKHealthStore, exportTargets: [ExportTarget]) throws {
        for exportTarget in exportTargets {
            try exportTarget.startWriteType(type)
            try exportTarget.startWriteDatas()
        }

        var result : (anchor:HKQueryAnchor?, count:Int?) = (anchor:nil, count: -1)
        repeat {
            result = try anchorQuery(healthStore, exportTargets: exportTargets, anchor:result.anchor)
        } while result.count != 0 || result.count==queryCountLimit

        for exportTarget in exportTargets {
            try exportTarget.endWriteDatas()
            try exportTarget.endWriteType()
        }

    }
    
}

internal class WorkoutDataExporter: BaseDataExporter, DataExporter {
    internal var message = "exporting workouts data"

    internal func export(healthStore: HKHealthStore, exportTargets: [ExportTarget]) throws {
        

        let semaphore = dispatch_semaphore_create(0)

        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: exportConfiguration.getPredicate(), limit: Int(HKObjectQueryNoLimit), sortDescriptors: [sortDescriptor]) { (query, tmpResult, error) -> Void in
            

            if error != nil {
                self.healthQueryError = error
            } else {
                do {
                    for exportTarget in exportTargets {
                        try exportTarget.startWriteType(HKObjectType.workoutType())
                        try exportTarget.startWriteDatas()
                    }
                    
                    for sample in tmpResult as! [HKWorkout] {
                        
                        var dict: Dictionary<String, AnyObject> = [:]
                        
                        dict["uuid"]                = sample.UUID.UUIDString
                        dict["sampleType"]          = sample.sampleType.identifier
                        dict["workoutActivityType"] = sample.workoutActivityType.rawValue
                        dict["sDate"]               = sample.startDate
                        dict["eDate"]               = sample.endDate
                        dict["duration"]            =  sample.duration // seconds
                        dict["totalDistance"]       = sample.totalDistance?.doubleValueForUnit(HKUnit.meterUnit())
                        dict["totalEnergyBurned"]   = sample.totalEnergyBurned?.doubleValueForUnit(HKUnit.kilocalorieUnit())

                        var workoutEvents: [Dictionary<String, AnyObject>] = []
                        for event in sample.workoutEvents ?? [] {
                            var workoutEvent: Dictionary<String, AnyObject> = [:]

                            workoutEvent["type"] =  event.type.rawValue
                            workoutEvent["startDate"] = event.date
                            workoutEvents.append(workoutEvent)
                        }

                        dict["workoutEvents"]       = workoutEvents
                        
                        for exportTarget in exportTargets {
                            try exportTarget.writeDictionary(dict);
                        }
                    }
                    
                    for exportTarget in exportTargets {
                        try exportTarget.endWriteDatas()
                        try exportTarget.endWriteType()
                    }
                    
                } catch let err {
                    self.exportError = err
                }
            }
            
            dispatch_semaphore_signal(semaphore)
        
        }
        
        healthStore.executeQuery(query)
        
        // wait for asyn call to complete
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        
        try rethrowCollectedErrors()
    }
}