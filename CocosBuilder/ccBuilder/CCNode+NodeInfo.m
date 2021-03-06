//
//  CCNode+NodeInfo.m
//  CocosBuilder
//
//  Created by Viktor Lidholt on 5/31/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "CCNode+NodeInfo.h"
#import "NodeInfo.h"
#import "PlugInNode.h"
#import "SequencerNodeProperty.h"
#import "SequencerKeyframe.h"
#import "SequencerKeyframeEasing.h"
#import "CocosBuilderAppDelegate.h"
#import "SequencerHandler.h"
#import "SequencerSequence.h"
#import "PositionPropertySetter.h"
#import "TexturePropertySetter.h"
#import "CCBWriterInternal.h"
#import "CCBReaderInternal.h"
#import "CCBDocument.h"

@implementation CCNode (NodeInfo)

- (void) setExtraProp:(id)prop forKey:(NSString *)key
{
    NodeInfo* info = self.userObject;
    [info.extraProps setObject:prop forKey:key];
}

- (id) extraPropForKey:(NSString *)key
{
    NodeInfo* info = self.userObject;
    return [info.extraProps objectForKey:key];
}

- (void) setSeqExpanded:(BOOL)seqExpanded
{
    [self setExtraProp:[NSNumber numberWithBool:seqExpanded] forKey:@"seqExpanded"];
}

- (BOOL) seqExpanded
{
    return [[self extraPropForKey:@"seqExpanded"] boolValue];
}

- (PlugInNode*) plugIn
{
    NodeInfo* info = self.userObject;
    return info.plugIn;
}

- (id) baseValueForProperty:(NSString*)name
{
    NodeInfo* info = self.userObject;
    return [info.baseValues objectForKey:name];
}

- (void) setBaseValue:(id)value forProperty:(NSString*)name
{
    NodeInfo* info = self.userObject;
    [info.baseValues setObject:value forKey:name];
}

- (SequencerNodeProperty*) sequenceNodeProperty:(NSString*)name sequenceId:(int)seqId
{
    NodeInfo* info = self.userObject;
    NSDictionary* dict = [info.animatableProperties objectForKey:[NSNumber numberWithInt:seqId]];
    return [dict objectForKey:name];
}

- (void) enableSequenceNodeProperty:(NSString*)name sequenceId:(int)seqId
{
    // Check if animations are already enabled for this node property
    if ([self sequenceNodeProperty:name sequenceId:seqId])
    {
        return;
    }
    
    // Get the right seqence, create one if neccessary
    NodeInfo* info = self.userObject;
    NSMutableDictionary* sequences = [info.animatableProperties objectForKey:[NSNumber numberWithInt:seqId]];
    if (!sequences)
    {
        sequences = [NSMutableDictionary dictionary];
        [info.animatableProperties setObject:sequences forKey:[NSNumber numberWithInt:seqId]];
    }
    
    id baseValue = [self valueForProperty:name atTime:0 sequenceId:seqId];
    
    SequencerNodeProperty* seqNodeProp = [[SequencerNodeProperty alloc] initWithProperty:name node:self];
    if (![info.baseValues objectForKey:name])
    {
        NSLog(@"setting baseValue to %@ for %@", baseValue, name);
        [info.baseValues setObject:baseValue forKey:name];
    }
    
    [sequences setObject:seqNodeProp forKey:name];
}

- (void) addKeyframe:(SequencerKeyframe*)keyframe forProperty:(NSString*)name atTime:(float)time sequenceId:(int)seqId
{
    // Check so we are not adding a keyframe out of bounds
    NSArray* seqs = [CocosBuilderAppDelegate appDelegate].currentDocument.sequences;
    SequencerSequence* seq = NULL;
    for (SequencerSequence* seqt in seqs)
    {
        if (seqt.sequenceId == seqId)
        {
            seq = seqt;
            break;
        }
    }
    if (time > seq.timelineLength) return;
    
    // Save undo state
    [[CocosBuilderAppDelegate appDelegate] saveUndoStateWillChangeProperty:@"*addkeyframe"];
    
    // Make sure timeline is enabled for this property
    [self enableSequenceNodeProperty:name sequenceId:seqId];
    
    // Add the keyframe
    SequencerNodeProperty* seqNodeProp = [self sequenceNodeProperty:name sequenceId:seqId];
    keyframe.parent = seqNodeProp;
    [seqNodeProp setKeyframe:keyframe];
    
    // Update property inspector
    [[CocosBuilderAppDelegate appDelegate] updateInspectorFromSelection];
    [[SequencerHandler sharedHandler] redrawTimeline];
    [self updateProperty:name time:[SequencerHandler sharedHandler].currentSequence.timelinePosition sequenceId:seqId];
}

- (void) addDefaultKeyframeForProperty:(NSString*)name atTime:(float)time sequenceId:(int)seqId
{
    // Get property type
    NSString* propType = [self.plugIn propertyTypeForProperty:name];
    int keyframeType = [SequencerKeyframe keyframeTypeFromPropertyType:propType];
    
    // Ensure that the keyframe type is supported
    if (!keyframeType)
    {
        return;
    }
    
    // Create keyframe
    SequencerKeyframe* keyframe = [[[SequencerKeyframe alloc] init] autorelease];
    keyframe.time = time;
    keyframe.type = keyframeType;
    keyframe.name = name;
    
    if (keyframeType == kCCBKeyframeTypeSpriteFrame)
    {
        keyframe.easing.type = kCCBKeyframeEasingInstant;
    }
    
    if (keyframeType == kCCBKeyframeTypeVisible)
    {
        // Values for visiblity keyframes are ignored (each keyframe toggles the state)
        keyframe.value = [NSNumber numberWithBool:YES];
    }
    else
    {
        // Get the interpolated value
        keyframe.value = [self valueForProperty:name atTime:time sequenceId:seqId];
    }
    
    [self addKeyframe:keyframe forProperty:name atTime:time sequenceId:seqId];
}

- (void) duplicateKeyframesFromSequenceId:(int)fromSeqId toSequenceId:(int)toSeqId
{
    NodeInfo* info = self.userObject;
    
    NSMutableDictionary* fromNodeProps = [info.animatableProperties objectForKey:[NSNumber numberWithInt:fromSeqId]];
    if (fromNodeProps)
    {
        for (NSString* propName in fromNodeProps)
        {
            SequencerNodeProperty* fromSeqNodeProp = [fromNodeProps objectForKey:propName];
            SequencerNodeProperty* toSeqNodeProp = [fromSeqNodeProp duplicate];
            
            [self enableSequenceNodeProperty:propName sequenceId:toSeqId];
            
            NSMutableDictionary* toNodeProps = [info.animatableProperties objectForKey:[NSNumber numberWithInt:toSeqId]];
            [toNodeProps setObject:toSeqNodeProp forKey:propName];
        }
    }
    
    
    // Also do for children
    CCNode* child = NULL;
    CCARRAY_FOREACH([self children], child)
    {
        [child duplicateKeyframesFromSequenceId:fromSeqId toSequenceId:toSeqId];
    }
}

- (id) valueForProperty:(NSString*)name atTime:(float)time sequenceId:(int)seqId
{
    SequencerNodeProperty* seqNodeProp = [self sequenceNodeProperty:name sequenceId:seqId];
    
    int type = [SequencerKeyframe keyframeTypeFromPropertyType:[self.plugIn propertyTypeForProperty:name]];
    
    // Check that type is supported
    NSAssert(type, @"Unsupported animated property type (%@)",[self.plugIn propertyTypeForProperty:name]);
    
    id seqValue = NULL;
    if (seqNodeProp)
    {
        seqValue = [seqNodeProp valueAtTime:time];
    }
    if (seqValue) return seqValue;
    
    // Check for base value
    NodeInfo* info = self.userObject;
    
    id baseValue = [info.baseValues objectForKey:name];
    if (baseValue)
    {
        return baseValue;
    }
    
    // Just use standard value
    if (type == kCCBKeyframeTypeDegrees
        || type == kCCBKeyframeTypeByte)
    {
        return [self valueForKey:name];
    }
    else if (type == kCCBKeyframeTypePosition)
    {
        CGPoint pos = [PositionPropertySetter positionForNode:self prop:name];
        return [NSArray arrayWithObjects:
                [NSNumber numberWithFloat:pos.x],
                [NSNumber numberWithFloat:pos.y],
                nil];
    }
    else if (type == kCCBKeyframeTypeScaleLock)
    {
        float x = [PositionPropertySetter scaleXForNode:self prop:name];
        float y = [PositionPropertySetter scaleYForNode:self prop:name];
        return [NSArray arrayWithObjects:
                [NSNumber numberWithFloat:x],
                [NSNumber numberWithFloat:y],
                nil];
    }
    else if (type == kCCBKeyframeTypeVisible)
    {
        return [self valueForKey:@"visible"];
    }
    else if (type == kCCBKeyframeTypeColor3)
    {
        NSValue* colorValue = [self valueForKey:name];
        ccColor3B c;
        [colorValue getValue:&c];
        return [CCBWriterInternal serializeColor3:c];
    }
    else if (type == kCCBKeyframeTypeSpriteFrame)
    {
        //[TexturePropertySetter 
        NSString* sprite = [self extraPropForKey:name];
        NSString* sheet = [self extraPropForKey:[name stringByAppendingString:@"Sheet"]];
        
        return [NSArray arrayWithObjects:sprite, sheet, nil];
    }
    
    return NULL;
}

- (void) updateProperty:(NSString*) propName time:(float)time sequenceId:(int)seqId
{
    int type = [SequencerKeyframe keyframeTypeFromPropertyType:[self.plugIn propertyTypeForProperty:propName]];
    
    if (!type) return;
    
    id value = [self valueForProperty:propName atTime:time sequenceId:seqId];
    
    if (type == kCCBKeyframeTypeDegrees)
    {
        [self setValue:value forKey:propName];
    }
    else if (type == kCCBKeyframeTypePosition)
    {
        NSPoint pos = NSZeroPoint;
        pos.x = [[value objectAtIndex:0] floatValue];
        pos.y = [[value objectAtIndex:1] floatValue];
        
        [PositionPropertySetter setPosition: pos forNode:self prop:propName];
    }
    else if (type == kCCBKeyframeTypeScaleLock)
    {
        float x = [[value objectAtIndex:0] floatValue];
        float y = [[value objectAtIndex:1] floatValue];
        int type = [PositionPropertySetter scaledFloatTypeForNode:self prop:propName];
        
        [PositionPropertySetter setScaledX:x Y:y type:type forNode:self prop:propName];
    }
    else if (type == kCCBKeyframeTypeVisible)
    {
        [self setValue:value forKey:propName];
    }
    else if (type == kCCBKeyframeTypeColor3)
    {
        ccColor3B c = [CCBReaderInternal deserializeColor3:value];
        NSValue* colorValue = [NSValue value:&c withObjCType:@encode(ccColor3B)];
        [self setValue:colorValue forKey:propName];
        
    }
    else if (type == kCCBKeyframeTypeSpriteFrame)
    {
        NSString* sprite = [value objectAtIndex:0];
        NSString* sheet = [value objectAtIndex:1];
        
        [TexturePropertySetter setSpriteFrameForNode:self andProperty:propName withFile:sprite andSheetFile:sheet];
    }
    else if (type == kCCBKeyframeTypeByte)
    {
        [self setValue:value forKey:propName];
    }
}

- (void) updatePropertiesTime:(float)time sequenceId:(int)seqId
{
    [self updateProperty:@"visible" time:time sequenceId:seqId];
    
    NSArray* animatableProps = [self.plugIn animatableProperties];
    for (NSString* propName in animatableProps)
    {
        [self updateProperty:propName time:time sequenceId:seqId];
    }
}

- (void) deselectAllKeyframes
{
    NodeInfo* info = self.userObject;
    
    NSEnumerator* animPropEnum = [info.animatableProperties objectEnumerator];
    NSDictionary* seq;
    while ((seq = [animPropEnum nextObject]))
    {
        NSEnumerator* seqEnum = [seq objectEnumerator];
        SequencerNodeProperty* prop;
        while ((prop = [seqEnum nextObject]))
        {
            for (SequencerKeyframe* keyframe in prop.keyframes)
            {
                keyframe.selected = NO;
            }
        }
    }
}

- (void) addSelectedKeyframesToArray:(NSMutableArray*)keyframes
{
    NodeInfo* info = self.userObject;
    
    NSEnumerator* animPropEnum = [info.animatableProperties objectEnumerator];
    NSDictionary* seq;
    while ((seq = [animPropEnum nextObject]))
    {
        NSEnumerator* seqEnum = [seq objectEnumerator];
        SequencerNodeProperty* prop;
        while ((prop = [seqEnum nextObject]))
        {
            for (SequencerKeyframe* keyframe in prop.keyframes)
            {
                if (keyframe.selected)
                {
                    [keyframes addObject:keyframe];
                }
            }
        }
    }
}

- (void) deleteSequenceId:(int) seqId
{
    NodeInfo* info = self.userObject;
    [info.animatableProperties removeObjectForKey:[NSNumber numberWithInt:seqId]];
    
    // Also remove for children
    CCNode* child = NULL;
    CCARRAY_FOREACH([self children], child)
    {
        [child deleteSequenceId:seqId];
    }
}

- (BOOL) deleteSelectedKeyframesForSequenceId:(int)seqId
{
    [[CocosBuilderAppDelegate appDelegate] saveUndoStateWillChangeProperty:@"*deletekeyframes"];
    
    BOOL deletedKeyframe = NO;
    
    NodeInfo* info = self.userObject;
    NSMutableDictionary* seq = [info.animatableProperties objectForKey:[NSNumber numberWithInt:seqId]];
    if (seq)
    {
        NSEnumerator* seqEnum = [seq objectEnumerator];
        SequencerNodeProperty* prop;
        NSMutableArray* emptyProps = [NSMutableArray array];
        while ((prop = [seqEnum nextObject]))
        {
            for (int i = prop.keyframes.count - 1; i >= 0; i--)
            {
                SequencerKeyframe* keyframe = [prop.keyframes objectAtIndex:i];
                if (keyframe.selected)
                {
                    [prop.keyframes removeObjectAtIndex:i];
                    deletedKeyframe = YES;
                }
            }
            if (prop.keyframes.count == 0)
            {
                [emptyProps addObject:prop.propName];
            }
        }
        
        // Remove empty seq node props
        for (NSString* propName in emptyProps)
        {
            [seq removeObjectForKey:propName];
        }
    }
    
    // Also remove keyframes for children
    CCNode* child = NULL;
    CCARRAY_FOREACH([self children], child)
    {
        if ([child deleteSelectedKeyframesForSequenceId:seqId])
        {
            deletedKeyframe = YES;
        }
    }
    return deletedKeyframe;
}

- (BOOL) deleteDuplicateKeyframesForSequenceId:(int)seqId
{
    BOOL deletedKeyframe = NO;
    
    NodeInfo* info = self.userObject;
    NSMutableDictionary* seq = [info.animatableProperties objectForKey:[NSNumber numberWithInt:seqId]];
    if (seq)
    {
        NSEnumerator* seqEnum = [seq objectEnumerator];
        SequencerNodeProperty* seqNodeProp;
        while ((seqNodeProp = [seqEnum nextObject]))
        {
            if ([seqNodeProp deleteDuplicateKeyframes])
            {
                deletedKeyframe = YES;
            }
        }
    }
    
    // Also remove keyframes for children
    CCNode* child = NULL;
    CCARRAY_FOREACH([self children], child)
    {
        if ([child deleteDuplicateKeyframesForSequenceId:seqId])
        {
            deletedKeyframe = YES;
        }
    }
    return deletedKeyframe;
}

- (void) deleteKeyframesAfterTime:(float)time sequenceId:(int)seqId
{
    NodeInfo* info = self.userObject;
    NSMutableDictionary* seq = [info.animatableProperties objectForKey:[NSNumber numberWithInt:seqId]];
    if (seq)
    {
        NSEnumerator* seqEnum = [seq objectEnumerator];
        SequencerNodeProperty* seqNodeProp;
        while ((seqNodeProp = [seqEnum nextObject]))
        {
            [seqNodeProp deleteKeyframesAfterTime:time];
        }
    }
    // Also remove keyframes for children
    CCNode* child = NULL;
    CCARRAY_FOREACH([self children], child)
    {
        [child deleteKeyframesAfterTime:time sequenceId:seqId];
    }
}

- (NSArray*) keyframesForProperty:(NSString*) prop
{
    NSMutableArray* keyframes = [NSMutableArray array];
    
    NodeInfo* info = self.userObject;
    
    NSEnumerator* animPropEnum = [info.animatableProperties objectEnumerator];
    NSDictionary* seq;
    while ((seq = [animPropEnum nextObject]))
    {
        SequencerNodeProperty* seqNodeProp = [seq objectForKey:prop];
        if (seqNodeProp)
        {
            [keyframes addObjectsFromArray:seqNodeProp.keyframes];
        }
    }
    return keyframes;
}

- (id) serializeAnimatedProperties
{
    NodeInfo* info = self.userObject;
    NSMutableDictionary* animatableProps = info.animatableProperties;
    if (!animatableProps.count)
    {
        return NULL;
    }
    
    NSMutableDictionary* serAnimatableProps = [NSMutableDictionary dictionaryWithCapacity:animatableProps.count];
    for (NSNumber* seqId in animatableProps)
    {
        NSMutableDictionary* properties = [animatableProps objectForKey:seqId];
        NSMutableDictionary* serProperties = [NSMutableDictionary dictionaryWithCapacity:animatableProps.count];
        
        for (NSString* propName in properties)
        {
            SequencerNodeProperty* seqNodeProp = [properties objectForKey:propName];
            [serProperties setObject:[seqNodeProp serialization] forKey:propName];
        }
        
        [serAnimatableProps setObject:serProperties forKey:[seqId stringValue]];
    }
    
    return serAnimatableProps;
}

- (void) loadAnimatedPropertiesFromSerialization:(id)ser
{
    NodeInfo* info = self.userObject;
    
    if (!ser)
    {
        info.animatableProperties = [NSMutableDictionary dictionary];
        return;
    }
    
    NSMutableDictionary* serAnimatableProps = ser;
    NSMutableDictionary* animatableProps = [NSMutableDictionary dictionaryWithCapacity:serAnimatableProps.count];
    
    for (NSString* seqId in serAnimatableProps)
    {
        NSMutableDictionary* serProperties = [serAnimatableProps objectForKey:seqId];
        NSMutableDictionary* properties = [NSMutableDictionary dictionaryWithCapacity:serProperties.count];
        
        for (NSString* propName in serProperties)
        {
            SequencerNodeProperty* seqNodeProp = [[[SequencerNodeProperty alloc] initWithSerialization:[serProperties objectForKey:propName]] autorelease];
            [properties setObject:seqNodeProp forKey:propName];
        }
        
        NSNumber* seqIdNum = [NSNumber numberWithInt:[seqId intValue]];
        
        [animatableProps setObject:properties forKey:seqIdNum];
    }
    
    info.animatableProperties = animatableProps;
}

@end
