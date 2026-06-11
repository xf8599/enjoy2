//
//  Config.m
//  Enjoy
//
//  Created by Sam McCall on 4/05/09.
//

@implementation Config

-(id) init {
	if(self=[super init]) {
		entries = [[NSMutableDictionary alloc] init];
	}
	return self;
}

@synthesize name, entries;

-(void) setTarget:(Target*)target forAction:(id)jsa {
	[entries setValue:target forKey: [jsa stringify]];
}
-(Target*) getTargetForAction: (id) jsa {
	return [entries objectForKey: [jsa stringify]];
}

-(void) saveJSONTo:(NSURL *)filename {
    NSMutableDictionary *mapping_dict = [NSMutableDictionary dictionary];
    [mapping_dict setObject:name forKey:@"name"];
    [mapping_dict setObject:@"enjoy3-1.1" forKey:@"format"];

    NSMutableDictionary *mapping_entries = [NSMutableDictionary dictionary];
    for (id key in entries) {
        [mapping_entries setObject:[[entries objectForKey:key] stringify] forKey:key];
    }
    [mapping_dict setObject:mapping_entries forKey:@"entries"];

    // Convert to JSON, write to file
    NSError *json_error = nil;
    NSData *json_data = [NSJSONSerialization dataWithJSONObject:mapping_dict
                                                       options:0
                                                         error:&json_error];
    if (json_data == nil) {
        NSLog(@"enjoy3: JSON 序列化失败: %@", json_error);
        return;
    }
    [json_data writeToURL:filename atomically:true];
}

-(Config*) loadSkelFromJSON:(NSData *)jsonData {
    NSError *json_error = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                         options:0
                                                           error:&json_error];
    if (dict == nil) {
        NSLog(@"enjoy3: JSON 反序列化失败: %@", json_error);
        return nil;
    }
    // Use the setter so the @property (copy) semantics copy + retain the string.
    [self setName:[dict objectForKey:@"name"]];
    return self;
}

-(Config*) loadFromJSON:(NSData *)jsonData withConfigList:(NSArray*)configs {
    NSError *json_error = nil;
    NSDictionary *jd = [NSJSONSerialization JSONObjectWithData:jsonData
                                                       options:0
                                                         error:&json_error];
    if (jd == nil) {
        NSLog(@"enjoy3: JSON 反序列化失败: %@", json_error);
        return nil;
    }
    NSString *jname = [jd objectForKey:@"name"];
    if (![jname isEqualToString:name]) {
        [NSException raise:@"Loading from JSON with different name" format:@"Loading from JSON with different name", nil];
    }

    NSDictionary *entries_d = [jd objectForKey:@"entries"];
    for(id key in entries_d) {
        NSString *value = [entries_d objectForKey:key];
        [entries setObject: [Target unstringify:value withConfigList:configs] forKey:key];
    }
    return self;
}

@end
