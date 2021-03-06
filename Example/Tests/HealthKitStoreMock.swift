//
//  HealthKitStoreMock.swift
//  HealthKitSampleGenerator
//
//  Created by Michael Seemann on 19.10.15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import HealthKit

public class HKBiologicalSexObjectMock: HKBiologicalSexObject {
    override public var biologicalSex: HKBiologicalSex {
        get {
            return HKBiologicalSex.male
        }
    }
}

public class HKBloodTypeObjectMock: HKBloodTypeObject {
    override public var bloodType: HKBloodType {
        get {
            return HKBloodType.aPositive
        }
    }
}

public class HKFitzpatrickSkinTypeObjectMock: HKFitzpatrickSkinTypeObject {
    override  public var skinType: HKFitzpatrickSkinType {
        get {
            return  HKFitzpatrickSkinType.I
        }
    }
}

class HealthKitStoreMock: HKHealthStore {
    
    override func dateOfBirth() throws -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"
        return dateFormatter.date(from: "01/30/1984")!
    }
    
    override func biologicalSex() throws -> HKBiologicalSexObject {
        return HKBiologicalSexObjectMock()
    }
    
    override func bloodType() throws -> HKBloodTypeObject {
        return HKBloodTypeObjectMock()
    }
    
    override func fitzpatrickSkinType() throws -> HKFitzpatrickSkinTypeObject {
        return HKFitzpatrickSkinTypeObjectMock()
    }

}
