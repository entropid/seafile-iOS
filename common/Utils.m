//
//  Utils.m
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//


#import "Utils.h"
#import "Debug.h"
#import "ExtentedString.h"

#import <sys/stat.h>
#import <dirent.h>
#import <sys/xattr.h>

#import "UIImage+fixOrientation.h"

@implementation Utils


+ (BOOL)addSkipBackupAttributeToItemAtPath:(NSString *)path
{
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *error = nil;
    [url setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsExcludedFromBackupKey error:&error];
    return error == nil;
}

+ (BOOL)checkMakeDir:(NSString *)path
{
    NSError *error;
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        //Does directory already exist?
        if (!isDirectory) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
        }
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
            Warning("Failed to create objects directory %@:%@\n", path, error);
            return NO;
        }
    }
    [Utils addSkipBackupAttributeToItemAtPath:path];
    return YES;
}

+ (void)clearAllFiles:(NSString *)path
{
    NSError *error;
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (!dirContents) {
        Warning("unable to get the contents of temporary directory\n");
        return;
    }

    for (NSString *entry in dirContents) {
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingPathComponent:entry] error:nil];
    }
}

+ (NSURL *)copyFile:(NSURL *)from to:(NSURL *)to
{
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:to.path]) {
        if ([fm copyItemAtURL:from toURL:to error:nil])
            return to;
        else
            return nil;
    }

    NSString *base = to.path.stringByDeletingPathExtension;
    NSString *suffix = to.pathExtension;
    NSString *testPath = nil;
    int maxIterations = 999;
    for (int i = 1; i <= maxIterations; i++) {
        if (suffix && suffix.length > 0)
            testPath = [NSString stringWithFormat:@"%@-%d.%@", base, i, suffix];
        else
            testPath = [NSString stringWithFormat:@"%@-%d", base, i];

        if ([fm fileExistsAtPath:testPath])
            continue;
        if ([fm copyItemAtPath:from.path toPath:testPath error:nil]) {
            return [NSURL fileURLWithPath:testPath];
        }
    }
    return nil;
}

+ (long long)fileSizeAtPath1:(NSString*)filePath
{
    NSFileManager* manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:filePath]){
        return [[manager attributesOfItemAtPath:filePath error:nil] fileSize];
    }
    return 0;
}

+ (long long)fileSizeAtPath2:(NSString*)filePath
{
    struct stat st;
    if(lstat([filePath cStringUsingEncoding:NSUTF8StringEncoding], &st) == 0){
        return st.st_size;
    }
    return 0;
}

+ (long long)folderSizeAtPath1:(NSString*)folderPath
{
    NSFileManager* manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:folderPath]) return 0;
    NSEnumerator *childFilesEnumerator = [[manager subpathsAtPath:folderPath] objectEnumerator];
    NSString* fileName;
    long long folderSize = 0;
    while ((fileName = [childFilesEnumerator nextObject]) != nil){
        NSString* fileAbsolutePath = [folderPath stringByAppendingPathComponent:fileName];
        folderSize += [self fileSizeAtPath1:fileAbsolutePath];
    }
    return folderSize;
}

+ (long long)folderSizeAtPath2:(NSString*)folderPath
{
    NSFileManager* manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:folderPath]) return 0;
    NSEnumerator *childFilesEnumerator = [[manager subpathsAtPath:folderPath] objectEnumerator];
    NSString* fileName;
    long long folderSize = 0;
    while ((fileName = [childFilesEnumerator nextObject]) != nil){
        NSString* fileAbsolutePath = [folderPath stringByAppendingPathComponent:fileName];
        folderSize += [self fileSizeAtPath2:fileAbsolutePath];
    }
    return folderSize;
}

+ (long long)_folderSizeAtPath:(const char*)folderPath
{
    long long folderSize = 0;
    DIR* dir = opendir(folderPath);
    if (dir == NULL) return 0;
    struct dirent* child;
    while ((child = readdir(dir))!=NULL) {
        if (child->d_type == DT_DIR && (
                                        (child->d_name[0] == '.' && child->d_name[1] == 0) ||
                                        (child->d_name[0] == '.' && child->d_name[1] == '.' && child->d_name[2] == 0)
                                        )) continue;

        long folderPathLength = strlen(folderPath);
        char childPath[1024];
        stpcpy(childPath, folderPath);
        if (folderPath[folderPathLength-1] != '/'){
            childPath[folderPathLength] = '/';
            folderPathLength++;
        }
        stpcpy(childPath+folderPathLength, child->d_name);
        childPath[folderPathLength + child->d_namlen] = 0;
        if (child->d_type == DT_DIR){
            folderSize += [self _folderSizeAtPath:childPath];
            struct stat st;
            if(lstat(childPath, &st) == 0) folderSize += st.st_size;
        }else if (child->d_type == DT_REG || child->d_type == DT_LNK){ // file or link
            struct stat st;
            if(lstat(childPath, &st) == 0) folderSize += st.st_size;
        }
    }
    return folderSize;
}

+ (long long)folderSizeAtPath:(NSString*)folderPath
{
    return [self _folderSizeAtPath:[folderPath cStringUsingEncoding:NSUTF8StringEncoding]];
}

+ (id)JSONDecode:(NSData *)data error:(NSError **)error
{
    NSString *rawData = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([rawData hasPrefix:@"\""] && [rawData hasSuffix:@"\""]) {
        return [rawData substringWithRange:NSMakeRange(1, [rawData length] - 2)];
    }
    id ret = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (*error)
        Warning("Parse json error:%@, %@\n", *error, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    return ret;
}

+ (NSData *)JSONEncode:(id)obj
{
    if ([obj isKindOfClass:[NSString class]]) {
        return [(NSString *)obj dataUsingEncoding:NSUTF8StringEncoding];
    }
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj
                                                       options:(NSJSONWritingOptions)0
                                                         error:&error];
    if (!jsonData) {
        Warning("Failed to encode Dictionary, error: %@", error.localizedDescription);
    }
    return jsonData;
}

+ (NSString *)JSONEncodeDictionary:(NSDictionary *)dict
{
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                       options:(NSJSONWritingOptions)0
                                                         error:&error];
    if (!jsonData) {
        Warning("Failed to encode Dictionary, error: %@", error.localizedDescription);
        return @"{}";
    } else {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
}

+ (BOOL)tryTransformEncoding:(NSString *)outfile fromFile:(NSString *)fromfile
{
    NSString *content = [Utils stringContent:fromfile];
    if (!content) return NO;
    [content writeToFile:outfile atomically:YES encoding:NSUTF16StringEncoding error:nil];
    return YES;
}

+ (NSString *)stringContent:(NSString *)path
{
    if ([Utils fileSizeAtPath1:path] > 10 * 1024 * 1024)
        return nil;
    NSString *encodeContent;
    NSStringEncoding encode;
    encodeContent = [NSString stringWithContentsOfFile:path usedEncoding:&encode error:nil];
    if (!encodeContent) {
        int i = 0;
        NSStringEncoding encodes[] = {
            NSUTF8StringEncoding,
            CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000),
            CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_2312_80),
            CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGBK_95),
            NSUnicodeStringEncoding,
            NSASCIIStringEncoding,
            0,
        };
        while (encodes[i]) {
            encodeContent = [NSString stringWithContentsOfFile:path encoding:encodes[i] error:nil];
             if (encodeContent) {
                Debug("use encoding %d, %ld\n", i, (unsigned long)encodes[i]);
                break;
            }
            ++i;
        }
    }
    return encodeContent;
}

+ (BOOL)isImageFile:(NSString *)name
{
    NSString *ext = name.pathExtension.lowercaseString;
    return [Utils isImageExt:ext];
}

+ (BOOL)isImageExt:(NSString *)ext
{
    static NSString *imgexts[] = {@"tif", @"tiff", @"jpg", @"jpeg", @"gif", @"png", @"bmp", @"ico", nil};
    if (!ext || ext.length != 0)
        return false;

    for (int i = 0; imgexts[i]; ++i) {
        if ([imgexts[i] isEqualToString:ext])
            return true;
    }
    return false;
}


+ (BOOL)writeDataToPathNoMeta:(NSString*)filePath andAsset:(ALAsset*)asset
{
    [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    if (!handle) {
        return NO;
    }
    static const NSUInteger BufferSize = 1024*1024;

    ALAssetRepresentation *rep = [asset defaultRepresentation];
    uint8_t *buffer = calloc(BufferSize, sizeof(*buffer));
    NSUInteger offset = 0, bytesRead = 0;

    do {
        @try {
            bytesRead = [rep getBytes:buffer fromOffset:offset length:BufferSize error:nil];
            [handle writeData:[NSData dataWithBytesNoCopy:buffer length:bytesRead freeWhenDone:NO]];
            offset += bytesRead;
        } @catch (NSException *exception) {
            free(buffer);
            return NO;
        }
    } while (bytesRead > 0);

    free(buffer);
    return YES;
}

+ (BOOL)writeDataToPathWithMeta:(NSString*)filePath andAsset:(ALAsset*)asset
{
    ALAssetRepresentation *defaultRep = asset.defaultRepresentation;
    UIImage *image = [UIImage imageWithCGImage:defaultRep.fullResolutionImage scale:defaultRep.scale orientation:(UIImageOrientation)defaultRep.orientation];
    NSData *currentImageData = UIImageJPEGRepresentation(image.fixOrientation, 1.0);
    [currentImageData writeToFile:filePath atomically:YES];
    return YES;
}

+ (BOOL)writeDataToPath:(NSString*)filePath andAsset:(ALAsset*)asset
{
    NSString *ext = filePath.pathExtension.lowercaseString;
    if ([@"jpg" isEqualToString:ext] || [@"jpeg" isEqualToString:ext])
        return [Utils writeDataToPathWithMeta:filePath andAsset:asset];
    return [Utils writeDataToPathNoMeta:filePath andAsset:asset];
}

+ (BOOL)fileExistsAtPath:(NSString *)path
{
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (CGSize)textSizeForText:(NSString *)txt font:(UIFont *)font width:(float)width
{
    CGFloat maxWidth = width;
    CGFloat maxHeight = 1000;

    CGRect stringRect = [txt boundingRectWithSize:CGSizeMake(maxWidth, maxHeight)
                                          options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:@{ NSFontAttributeName : font }
                                          context:nil];

    CGSize stringSize = CGRectIntegral(stringRect).size;

    return CGSizeMake(roundf(stringSize.width), roundf(stringSize.height));
}

+ (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)())yes no:(void (^)())no from:(UIViewController *)c
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *yesAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"YES", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (yes) yes();
    }];
    UIAlertAction *noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"NO", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (no) no();
    }];

    [alert addAction:noAction];
    [alert addAction:yesAction];
    [c presentViewController:alert animated:true completion:nil];
}

+ (void)alertWithTitle:(NSString *)title message:(NSString*)message handler:(void (^)())handler from:(UIViewController *)c
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (handler)
            handler();
    }];
    [alert addAction:okAction];
    [c presentViewController:alert animated:true completion:nil];
}

+ (void)popupInputView:(NSString *)title placeholder:(NSString *)tip secure:(BOOL)secure handler:(void (^)(NSString *input))handler from:(UIViewController *)c
{
    [self popupInputView:title placeholder:tip prefilled:NO secure:secure handler:handler from:c];
}

+ (void)popupInputView:(NSString *)title placeholder:(NSString *)tip prefilled:(BOOL)prefilled secure:(BOOL)secure handler:(void (^)(NSString *))handler from:(UIViewController *)c
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    }];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = [[alert.textFields objectAtIndex:0] text];
        if (handler)
            handler(input);
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = tip;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.secureTextEntry = secure;
        
        if (prefilled) {
            textField.text = tip;
        }
    }];
    [alert addAction:cancelAction];
    [alert addAction:okAction];
    
    [c presentViewController:alert animated:true completion:nil];
}

+ (UIImage *)reSizeImage:(UIImage *)image toSquare:(float)length
{
    CGSize reSize;
    CGSize size = image.size;
    if (size.height > size.width) {
        reSize = CGSizeMake(length * size.width / size.height, length);
    } else {
        reSize = CGSizeMake(length, length * size.height / size.width);
    }

    UIGraphicsBeginImageContext(CGSizeMake(reSize.width, reSize.height));
    [image drawInRect:CGRectMake(0, 0, reSize.width, reSize.height)];
    UIImage *reSizeImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return reSizeImage;
}


@end
