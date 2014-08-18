/**
 * This file is part of Todo.txt, an iOS app for managing your todo.txt file.
 *
 * @author Todo.txt contributors <todotxt@yahoogroups.com>
 * @copyright 2011-2013 Todo.txt contributors (http://todotxt.com)
 *  
 * Dual-licensed under the GNU General Public License and the MIT License
 *
 * @license GNU General Public License http://www.gnu.org/licenses/gpl.html
 *
 * Todo.txt is free software: you can redistribute it and/or modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation, either version 2 of the License, or (at your option) any
 * later version.
 *
 * Todo.txt is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with Todo.txt.  If not, see
 * <http://www.gnu.org/licenses/>.
 *
 *
 * @license The MIT License http://www.opensource.org/licenses/mit-license.php
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
#import "Task.h"
#import "TextSplitter.h"
#import "ContextParser.h"
#import "ProjectParser.h"
#import "RelativeDate.h"
#import "Util.h"

#define COMPLETED_TXT @"x "
#define TASK_DATE_FORMAT @"yyyy-MM-dd"

NSDateFormatter *taskDateFormatter;

@interface RepeatSpecification: NSObject
@property NSDateComponents *interval;
@property int lead;
@property BOOL approx;
@end

@implementation RepeatSpecification
@end

@implementation Task

@synthesize originalText, originalPriority;
@synthesize taskId, priority, deleted, completed, text;
@synthesize completionDate, prependedDate, relativeAge;
@synthesize contexts, projects;
@synthesize dueDate, isDue, isOverdue, isWayOverdue, isPaused;

- (void)populateWithTaskId:(NSUInteger)newId withRawText:(NSString*)rawText withDefaultPrependedDate:(NSDate*)date {
	taskId = newId;
	
	TextSplitter *splitResult = [TextSplitter split:rawText];
	
	priority = [splitResult priority];
	text = [splitResult text];
	prependedDate = [splitResult prependedDate];
	completed = [splitResult completed];
	completionDate = [splitResult completedDate];
    dueDate = self.calculateDueDate;

	contexts = [ContextParser parse:text];
	projects = [ProjectParser parse:text];
	deleted = [text length] == 0;
	
	if (date && [prependedDate length] == 0) {
		prependedDate = [Util stringFromDate:date withFormat:TASK_DATE_FORMAT];
	}

	if ([prependedDate length] > 0) {
		relativeAge = [RelativeDate 
						stringWithDate:[Util dateFromString:prependedDate 
										withFormat:TASK_DATE_FORMAT]];
	}

    if (dueDate != nil) {
        [self updateDueFlags];
    }

}

- (id)initWithId:(NSUInteger)newID withRawText:(NSString*)rawText withDefaultPrependedDate:(NSDate*)date {
	self = [super init];

    if (taskDateFormatter == nil) {
        taskDateFormatter = [[NSDateFormatter alloc] init];
        taskDateFormatter.dateFormat = TASK_DATE_FORMAT;
    }

	if (self) {
		[self populateWithTaskId:newID withRawText:rawText withDefaultPrependedDate:date];
		originalPriority = priority;
		originalText = text;
	}
	
	return self;
}

- (id)initWithId:(NSUInteger)taskID withRawText:(NSString*)rawText {
	return [self initWithId:taskID withRawText:rawText withDefaultPrependedDate:nil];
}

- (void)update:(NSString*)rawText {
	[self populateWithTaskId:taskId withRawText:rawText withDefaultPrependedDate:nil];
}

- (void)markComplete:(NSDate*)date {
	if (!completed) {
        RepeatSpecification *rep = self.repeatInterval;
        if (dueDate != nil && rep != nil) {
            NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
            if (rep.approx) {
                [self updateDueDate:[cal dateByAddingComponents:rep.interval toDate:[[NSDate alloc] init] options:0]];
            } else {
                [self updateDueDate:[cal dateByAddingComponents:rep.interval toDate:dueDate options:0]];
            }
        } else {
            priority = [Priority NONE];
            completionDate = [Util stringFromDate:date withFormat:TASK_DATE_FORMAT];
            deleted = NO;
            completed = YES;
        }
        if (isPaused) {
            [self togglePause];
        }
	}
}

- (void)markIncomplete {
	if (completed) {
		completionDate = [NSString string];
		completed = NO;
	}
}

- (void)togglePause {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\s+pause:\\S+\\b" options:0 error:nil];
    NSTextCheckingResult *tcr = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (tcr != nil) {
        text = [text stringByReplacingCharactersInRange:tcr.range withString:@""];
    } else {
        text = [text stringByAppendingString:@" pause:1"];
    }
}

- (void)deleteTask {
	[self update:@""];
}

- (NSString*)inScreenFormat{
	NSMutableString *ret = [NSMutableString stringWithCapacity:[text length] + 32];
	
	if (completed) {
		[ret appendString:COMPLETED_TXT];
		[ret appendString:completionDate];
		[ret appendString:@" "];
		if ([prependedDate length] > 0) {
			[ret appendString:prependedDate];
			[ret appendString:@" "];
		}		
	}

    [ret appendString:text];

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\s+due:\\S+\\b" options:0 error:nil];
    NSTextCheckingResult *tcr = [re firstMatchInString:ret options:0 range:NSMakeRange(0, ret.length)];
    if (tcr != nil) {
        [ret deleteCharactersInRange:tcr.range];
    }

    re = [NSRegularExpression regularExpressionWithPattern:@"\\s+rep:\\S+\\b" options:0 error:nil];
    tcr = [re firstMatchInString:ret options:0 range:NSMakeRange(0, ret.length)];
    if (tcr != nil) {
        [ret deleteCharactersInRange:tcr.range];
    }

    re = [NSRegularExpression regularExpressionWithPattern:@"\\s+pause:\\S+\\b" options:0 error:nil];
    tcr = [re firstMatchInString:ret options:0 range:NSMakeRange(0, ret.length)];
    if (tcr != nil) {
        [ret deleteCharactersInRange:tcr.range];
    }

	return [ret copy];
}

- (NSString*)inFileFormat{
	NSMutableString *ret = [NSMutableString stringWithCapacity:[text length] + 32];
	
	if (completed) {
		[ret appendString:COMPLETED_TXT];
		[ret appendString:completionDate];
		[ret appendString:@" "];
	} else {
		if (priority != [Priority NONE]) {
			[ret appendString:[priority fileFormat]];
			[ret appendString:@" "];
		}
	}
	
	if ([prependedDate length] > 0) {
		[ret appendString:prependedDate];
		[ret appendString:@" "];
	}

	[ret appendString:text];
	
	return [ret copy];
}

- (void)copyInto:(Task*)destination {
	[destination populateWithTaskId:taskId withRawText:[self inFileFormat] withDefaultPrependedDate:nil];
}

- (BOOL)isEqual:(id)anObject{
	if (self == anObject) {
		return YES;
	}
	
	if (anObject == nil || ![anObject isKindOfClass:[Task class]]) {
		return NO;
	}
	
	Task *task = (Task *)anObject;
	
	if (completed != [task completed]) {
		return NO;
	}
	
	if (deleted != [task deleted]) {
		return NO;
	}
	
	if (taskId != [task taskId]) {
		return NO;
	}
	
	if (priority != [task priority]) {
		return NO;
	}
	
	if (![contexts isEqualToArray:[task contexts]]) {
		return NO;
	}
	
	if (![prependedDate isEqualToString:[task prependedDate]]) {
		return NO;
	}
	
	if (![projects isEqualToArray:[task projects]]) {
		return NO;
	}
	
	if (![text isEqualToString:[task text]]) {
		return NO;
	}
	
	return YES;
}

- (NSUInteger)hash{
	NSUInteger result = taskId;
	result = 31 * result + [priority hash];
	result = 31 * result + (deleted ? 1 : 0);
	result = 31 * result + (completed ? 1 : 0);
	result = 31 * result + [text hash];
	result = 31 * result + [prependedDate hash];
	result = 31 * result + [contexts hash];
	result = 31 * result + [projects hash];
	return result;
}

/**
  * Returns the fully extended priority order: A - Z, None, Completed
  *
  * @return fullyExtendedPriority
  */
- (NSUInteger) sortPriority {
	if (completed) {
		return [[Priority all] count];
	}
	NSUInteger intVal = (NSUInteger) priority.name;
	return (priority != [Priority NONE] ? intVal - 1 : [[Priority all] count] - 1);
}

- (NSString*) ascSortDate {
	if (completed) {
		return @"9999-99-99";
	}
	if ([prependedDate length] == 0) {
		return @"9999-99-98";
	}
	return prependedDate;
}

- (NSString*) descSortDate {
	if (completed) {
		return @"0000-00-00";
	}
	if ([prependedDate length] == 0) {
		return @"9999-99-99";
	}
	return prependedDate;
}

- (NSComparisonResult) compareByIdAscending:(Task*)other {
	if (taskId < other.taskId) {
		return NSOrderedAscending;
	} else if (taskId > other.taskId) {
		return NSOrderedDescending;
	} else {
		return NSOrderedSame;
	}
}

- (NSComparisonResult) compareByIdDescending:(Task*)other {
	if (other.taskId < taskId) {
		return NSOrderedAscending;
	} else if (other.taskId > taskId) {
		return NSOrderedDescending;
	} else {
		return NSOrderedSame;
	}
}

- (NSComparisonResult) compareByTextAscending:(Task*)other {
	if (!completed && [other completed]) {
		return NSOrderedAscending;
	}
	if (completed && !other.completed) {
		return NSOrderedDescending;
	}
	
	NSComparisonResult ret = [text caseInsensitiveCompare:other.text];
	if (ret == NSOrderedSame) {
		ret = [self compareByIdAscending:other];
	}
	return ret;
}

- (NSComparisonResult) compareByPriority:(Task*)other {
	NSUInteger thisPri = [self sortPriority];
	NSUInteger otherPri = [other sortPriority];

    if (self.completed != other.completed) {
        return self.completed ? NSOrderedDescending : NSOrderedAscending;
    }
    if (self.isWayOverdue != other.isWayOverdue) {
        return self.isWayOverdue ? NSOrderedAscending : NSOrderedDescending;
    }
    if (self.isOverdue != other.isOverdue) {
        return self.isOverdue ? NSOrderedAscending : NSOrderedDescending;
    }
    if (self.isDue != other.isDue) {
        return self.isDue ? NSOrderedAscending : NSOrderedDescending;
    }
    if ((dueDate == nil) != (other->dueDate == nil)) {
        return dueDate == nil ? NSOrderedAscending : NSOrderedDescending;
    }

	if (thisPri < otherPri) {
		return NSOrderedAscending;
	} else if (thisPri > otherPri) {
		return NSOrderedDescending;
    } else if (dueDate != nil && other->dueDate != nil) {
        return [dueDate compare:other->dueDate];
	} else {
		return [self compareByIdAscending:other];
	}
}

- (NSComparisonResult) compareByDateAscending:(Task*)other {
	NSComparisonResult res = [[self ascSortDate] compare:[other ascSortDate]];
	if (res != NSOrderedSame) {
		return res;
	}
	return [self compareByIdAscending:other];
}

- (NSComparisonResult) compareByDateDescending:(Task*)other {
	NSComparisonResult res = [[other descSortDate] compare:[self descSortDate]];
	if (res != NSOrderedSame) {
		return res;
	}
	return [self compareByIdDescending:other];
}

- (NSArray *)rangesOfContexts:(NSString *)taskText
{
    return [ContextParser rangesOfContextsForString:taskText];
}

- (NSArray *)rangesOfProjects:(NSString *)taskText
{
    return [ProjectParser rangesOfProjectsForString:taskText];
}

- (NSDate *)calculateDueDate
{
    NSRegularExpression *repre = [NSRegularExpression regularExpressionWithPattern:@"\\bdue:(\\d{4}-\\d{2}-\\d{2})\\b" options:0 error:nil];
    NSTextCheckingResult *tcr = [repre firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (tcr == nil) {
        return nil;
    }
    return [Util dateFromString:[text substringWithRange:[tcr rangeAtIndex:1]] withFormat:TASK_DATE_FORMAT];
}

- (void)updateDueDate:(NSDate *)due
{
    NSRegularExpression *repre = [NSRegularExpression regularExpressionWithPattern:@"\\bdue:(\\d{4}-\\d{2}-\\d{2})\\b" options:0 error:nil];
    NSTextCheckingResult *tcr = [repre firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (tcr == nil) {
        return;
    }
    text = [text stringByReplacingCharactersInRange:[tcr rangeAtIndex:1] withString:[taskDateFormatter stringFromDate:due]];
    dueDate = due;
    [self updateDueFlags];
}

- (void)updateDueFlags
{
    NSDate *today = [[NSDate alloc] init];
    NSDate *notify = self.notifyDate;
    isDue = [notify compare:today] != NSOrderedDescending;
    isOverdue = [dueDate compare:today] != NSOrderedDescending;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    NSDateComponents *dc = [cal components:NSCalendarUnitDay fromDate:dueDate toDate:today options:0];
    isWayOverdue = dc.day >= 14;
    isPaused = [text rangeOfString:@"pause:1"].location != NSNotFound;

    relativeAge = @"";
    dc = [cal components:NSCalendarUnitDay fromDate:today toDate:dueDate options:0];
    if ([today compare:dueDate] == NSOrderedAscending) {
        dc.day++;
        relativeAge = [relativeAge stringByAppendingString:[NSString stringWithFormat:@"%ld day%@ left", dc.day, dc.day > 1 ? @"s" : @""]];
    } else if ([today compare:dueDate] == NSOrderedDescending && dc.day != 0) {
        dc.day = -dc.day;
        relativeAge = [relativeAge stringByAppendingString:[NSString stringWithFormat:@"%ld day%@ past", dc.day, dc.day > 1 ? @"s" : @""]];
    }
    relativeAge = [relativeAge stringByAppendingString:[NSString stringWithFormat:@" due %@", [taskDateFormatter stringFromDate:dueDate]]];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\s+rep:(\\S+)\\b" options:0 error:nil];
    NSTextCheckingResult *tcr = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (tcr != nil) {
        relativeAge = [relativeAge stringByAppendingString:[NSString stringWithFormat:@" rep %@", [text substringWithRange:[tcr rangeAtIndex:1]]]];
    }
}

- (RepeatSpecification *)repeatInterval
{
    NSRegularExpression *repre = [NSRegularExpression regularExpressionWithPattern:@"\\brep:(~)?(\\d+)([dwmy])(;(\\d+)d)?\\b" options:0 error:nil];
    NSTextCheckingResult *tcr = [repre firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (tcr == nil) {
        return nil;
    }
    RepeatSpecification *r = [[RepeatSpecification alloc] init];

    r.approx = [tcr rangeAtIndex:1].location != NSNotFound;

    NSString *scount = [text substringWithRange:[tcr rangeAtIndex:2]];
    NSString *sunit = [text substringWithRange:[tcr rangeAtIndex:3]];
    long count = [scount integerValue];
    NSDateComponents *dc = [[NSDateComponents alloc] init];
    switch ([sunit characterAtIndex:0]) {
        case 'd': dc.day = count; break;
        case 'w': dc.week = count; break;
        case 'm': dc.month = count; break;
        case 'y': dc.year = count; break;
    }
    r.interval = dc;

    if (r.approx) {
        r.lead = 1;
    } else {
        NSRange range = [tcr rangeAtIndex:5];
        if (range.location != NSNotFound) {
            r.lead = [[text substringWithRange:range] integerValue];
        } else {
            int repeat = 0;
            if (dc.day != NSUndefinedDateComponent) repeat += dc.day;
            if (dc.week != NSUndefinedDateComponent) repeat += 7 * dc.week;
            if (dc.month != NSUndefinedDateComponent) repeat += 30 * dc.month;
            if (dc.year != NSUndefinedDateComponent) repeat += 365 * dc.year;
            r.lead = floor(pow(repeat, 0.5));
        }
    }

    return r;
}

- (NSDate *)notifyDate
{
    NSDate *notifydate = dueDate;
    if (notifydate == nil) {
        return nil;
    }
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    RepeatSpecification *rep = self.repeatInterval;
    NSDateComponents *dc = [[NSDateComponents alloc] init];
    dc.day = rep != nil ? -rep.lead : -14;
    return [cal dateByAddingComponents:dc toDate:notifydate options:0];
}

- (void)updateOnSignificantTimeChange
{
    if (dueDate != nil) {
        [self updateDueFlags];
    }
}

- (UILocalNotification *)localNotification
{
    NSDate *alert = self.notifyDate;
    if ([alert compare:[[NSDate alloc] init]] != NSOrderedDescending) {
        return nil;
    }
    UILocalNotification *notif = [[UILocalNotification alloc] init];
    notif.fireDate = alert;
    notif.alertBody = [self inScreenFormat];
    return notif;
}

@end
