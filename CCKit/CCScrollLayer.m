//
//  CCScrollLayer.m
//  CCExtensions
//
//  Created by Jerrod Putman on 7/29/11.
//  Copyright 2011 Tiny Tim Games. All rights reserved.
//
//  Portions created by Sangwoo Im.
//
//  Modified by CJ Hanson @ Hanson Interactive.
//
//	Permission is hereby granted, free of charge, to any person obtaining a copy
//	of this software and associated documentation files (the "Software"), to deal
//	in the Software without restriction, including without limitation the rights
//	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//	copies of the Software, and to permit persons to whom the Software is
//	furnished to do so, subject to the following conditions:
//
//	The above copyright notice and this permission notice shall be included in
//	all copies or substantial portions of the Software.
//
//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//	THE SOFTWARE.
//

#import "CCScrollLayer.h"
#import "DeviceConfiguration.h"

//This sets how slowly the thing is sliding when we say it's close enough to stopped. (and animate it into a valid position)
//The value is in points per second squared (49 is basically 7 pps (squared))
//A bigger value will make it feel stickier and a smaller one will let it slide more but will also go very slowly for some time before it thinks it should stop
#define SCROLL_STOP_VELOCITY  (kUserInterfacePad?200.0f:120.0f)

//This is a cap on the individual x and y speed in points per second
//It applies after releasing the view and letting it slide to a stop
//It also factors into the duration of the Move animation for paging.
//In that case bigger values will cause it to snap into place faster
#define SCROLL_MAX_VELOCITY   (kUserInterfacePad?500.0f:300.0f)

//This is the distance you can drag the view beyond the ends in points
#define OVERSHOOT_DISTANCE    (kUserInterfacePad?80.0f:50.0f)

//This is used for Zoom (which is untested anyway)
#define BOUNCE_DURATION				0.20f

const float CCScrollLayerDecelerationRateNormal = 0.96f;
const float CCScrollLayerDecelerationRateFast = 0.86f;



@interface CCScrollLayer ()

@property (nonatomic, retain) CCLayer *container;

- (void)scrollLayerDidScroll;

@end


#pragma mark -


@implementation CCScrollLayer
{
  NSTimeInterval lastGestureTime;
  CGPoint lastGesturePoint;
  NSTimeInterval totalGestureTime;
  CGPoint totalGestureDistance;
  CGPoint scrollVelocity;
  BOOL isAnimating;
}

@synthesize scrollEnabled;
@synthesize direction;
@synthesize clipToBounds;
@synthesize viewSize;
@synthesize bounces;
@synthesize alwaysBounceHorizontal;
@synthesize alwaysBounceVertical;
@synthesize decelerationRate;
@synthesize decelerating;
@synthesize bouncesZoom;
@synthesize minimumZoom;
@synthesize maximumZoom;
@synthesize zoomBouncing;
@synthesize delegate;
@synthesize container;
@synthesize pagingEnabled;
@synthesize panGestureRecognizer;
@synthesize pinchGestureRecognizer;

@dynamic contentOffset;

- (void) dealloc
{
  [container release];
  [panGestureRecognizer release];
  [pinchGestureRecognizer release];
  [super dealloc];
}


#pragma mark - Private

- (CGPoint)maxContainerOffsetWithOvershot:(CGPoint)overshot
{
  CGPoint offset = ccpAdd(CGPointZero, overshot);
  
  if(direction == CCScrollLayerDirectionHorizontal)
    offset.y = 0;
  
  if(direction == CCScrollLayerDirectionVertical)
    offset.x = 0;
  
  return offset;
}

- (CGPoint)minContainerOffsetWithOvershot:(CGPoint)overshot
{
  CGPoint offset = ccp(viewSize.width - self.contentSize.width, viewSize.height - self.contentSize.height);
  
  offset = ccpSub(offset, overshot);
  
  if(direction == CCScrollLayerDirectionHorizontal)
    offset.y = 0;
  
  if(direction == CCScrollLayerDirectionVertical)
    offset.x = 0;
  
  return offset;
}

- (CGPoint) clampedPosition:(CGPoint)targetPos withOvershot:(CGPoint)overshot
{
  CGPoint maxInset    = [self maxContainerOffsetWithOvershot:overshot];
  CGPoint minInset    = [self minContainerOffsetWithOvershot:overshot];
  
  CGPoint clampPos    = targetPos;
  clampPos.x          = clampf(clampPos.x, maxInset.x, minInset.x);
  clampPos.y          = clampf(clampPos.y, maxInset.y, minInset.y);
  
  return clampPos;
}

- (void) update:(ccTime)delta
{
  BOOL shouldSendDidScroll = NO;
  
  if(!self.dragging && !self.zooming && decelerating && !isAnimating){
    scrollVelocity      = ccpMult(scrollVelocity, decelerationRate);
    CGPoint pVelocity   = ccpMult(scrollVelocity, delta);
    pVelocity.x         = clampf(pVelocity.x, -SCROLL_MAX_VELOCITY, SCROLL_MAX_VELOCITY);
    pVelocity.y         = clampf(pVelocity.y, -SCROLL_MAX_VELOCITY, SCROLL_MAX_VELOCITY);
    
    CGPoint newPos      = ccpAdd(container.position, pVelocity);
    
    CGPoint overshot    = (bounces)?ccp(OVERSHOOT_DISTANCE, OVERSHOOT_DISTANCE):CGPointZero;
    CGPoint clampPos    = [self clampedPosition:newPos withOvershot:overshot];
    
    container.position  = clampPos;
    
    shouldSendDidScroll = YES;
    
    BOOL isOutOfBounds  = NO;
    CGPoint moveTo      = CGPointZero;
    CGPoint maxInset    = [self maxContainerOffsetWithOvershot:CGPointZero];
    CGPoint minInset    = [self minContainerOffsetWithOvershot:CGPointZero];
    
    if(container.position.x > maxInset.x){
      isOutOfBounds = YES;
      moveTo.x = maxInset.x;
    }
    
    if(container.position.x < minInset.x){
      isOutOfBounds = YES;
      moveTo.x = minInset.x;
    }
    
    if(container.position.y > maxInset.y){
      isOutOfBounds = YES;
      moveTo.y = maxInset.y;
    }
    
    if(container.position.y < minInset.y){
      isOutOfBounds = YES;
      moveTo.y = minInset.y;
    }
    
    float pageF = 0;
    
    if(isOutOfBounds){
      scrollVelocity = ccpMult(scrollVelocity, 0.1f);
    }else if(pagingEnabled){
      //when it gets close to a page boundary add more friction
      if(direction == CCScrollLayerDirectionHorizontal)
        pageF = fabsf((container.position.x - viewSize.width/2.0)/viewSize.width);
      else
        pageF = fabsf((container.position.y - viewSize.height/2.0)/viewSize.height);
      
      float pageN;
      float distToPage = modff(pageF, &pageN);
      if(distToPage > 0.2f && distToPage < 0.8f)
        scrollVelocity = ccpMult(scrollVelocity, 0.2f);
    }
    
    if(ccpLengthSQ(scrollVelocity) < SCROLL_STOP_VELOCITY){
      if(isOutOfBounds){
        [self setContentOffset:moveTo animated:YES];
      }else if(pagingEnabled){
        int pageCount = self.pageCount;
        int page = (int)pageF;
        page = MAX(0, MIN(pageCount-1, page));
        [self scrollToPage:page animated:YES];
      }else{
        shouldSendDidScroll = NO;
        [self stoppedDecelerating:nil];
      }
		}
  }
  
  if(isAnimating)
    shouldSendDidScroll = YES;
  
  if(shouldSendDidScroll)
    [self scrollLayerDidScroll];
}

- (void) stoppedDecelerating:(id)sender
{
  [self scrollLayerDidScroll];
  
  if([delegate respondsToSelector:@selector(scrollLayerDidEndDecelerating:)])
    [delegate scrollLayerDidEndDecelerating:self];
  
  scrollVelocity = CGPointZero;
  decelerating = NO;
  isAnimating = NO;
}

- (void)scrollLayerDidScroll
{
	if([delegate respondsToSelector:@selector(scrollLayerDidScroll:)])
		[delegate scrollLayerDidScroll:self];
}

#pragma mark - Properties

- (int) pageCount
{
  if(direction == CCScrollLayerDirectionHorizontal)
    return container.contentSize.width / viewSize.width;
  else
    return container.contentSize.height / viewSize.height;
}

- (int) currentPage
{
  int pageCount = self.pageCount;
  int page = 0;
  if(direction == CCScrollLayerDirectionHorizontal)
    page = fabsf((container.position.x - viewSize.width/2.0)/viewSize.width);
  else
    page = fabsf((container.position.y - viewSize.height/2.0)/viewSize.height);
  
  page = MAX(0, MIN(pageCount-1, page));
  
  return page;
}

- (void) setCurrentPage:(int)page
{
  [self scrollToPage:page animated:NO];
}

- (void)setScrollEnabled:(BOOL)se
{
	panGestureRecognizer.enabled = se;
	pinchGestureRecognizer.enabled = se;
}


- (BOOL)dragging
{
	return (panGestureRecognizer.state == UIGestureRecognizerStateChanged);
}


- (BOOL)zooming
{
	return (pinchGestureRecognizer.state == UIGestureRecognizerStateChanged);
}


- (void)setContentOffset:(CGPoint)offset
{
    [self setContentOffset:offset animated:NO];
}


- (CGPoint)contentOffset
{
    return container.position;
}


- (void)setZoomScale:(float)zoomScale
{
	[self setZoomScale:zoomScale animated:NO];
}


- (float)zoomScale
{
	return container.scale;
}

#pragma mark - Creating a scroll view

+ (id)scrollLayerWithViewSize:(CGSize)size
{
    return [[[CCScrollLayer alloc] initWithViewSize:size] autorelease];
}


- (id)initWithViewSize:(CGSize)size
{
  self = [super init];
  
  if(self){
    viewSize = size;
    bounces = YES;
    decelerationRate = CCScrollLayerDecelerationRateNormal;
    clipToBounds = YES;
    pagingEnabled = NO;
    direction = CCScrollLayerDirectionBoth;
    minimumZoom = 1.0f;
    maximumZoom = 1.0f;

    panGestureRecognizer  = [[UIPanGestureRecognizer alloc] init];
    panGestureRecognizer.delaysTouchesBegan = YES;
    panGestureRecognizer.delegate = self;
    [panGestureRecognizer addTarget:self action:@selector(handlePanGesture:)];

    pinchGestureRecognizer  = [[UIPinchGestureRecognizer alloc] init];
    pinchGestureRecognizer.delegate = self;
    [pinchGestureRecognizer addTarget:self action:@selector(handlePinchGesture:)];

    container = [[CCLayer alloc] init];
    container.contentSize = CGSizeZero;
    container.position = ccp(0.0f, 0.0f);
    [self addChild:container];
  }

  return self;
}


- (id)init
{
  self = [self initWithViewSize:[[CCDirector sharedDirector] winSize]];
  return self;
}


#pragma mark - Scene presentation

- (void)onEnterTransitionDidFinish
{
  [super onEnterTransitionDidFinish];
  
	[self addGestureRecognizer:panGestureRecognizer];
	[self addGestureRecognizer:pinchGestureRecognizer];
  
  [self scheduleUpdate];
}

- (void)onExit
{
  [super onExit];
  
	[self removeGestureRecognizer:panGestureRecognizer];
	[self removeGestureRecognizer:pinchGestureRecognizer];
  
  [self unscheduleUpdate];
}

- (void)addGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
{
	[[CCDirector sharedDirector].view addGestureRecognizer:gestureRecognizer];
}

- (void)removeGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
{
  [[CCDirector sharedDirector].view removeGestureRecognizer:gestureRecognizer];
}


#pragma mark - Managing scrolling

- (void)scrollRectToVisible:(CGRect)rect animated:(BOOL)animated
{
	CGPoint centerOfRect = CGPointMake(rect.origin.x + rect.size.width / 2 - viewSize.width / 2, rect.origin.y + rect.size.height / 2 - viewSize.height / 2);
	[self setContentOffset:centerOfRect animated:animated];
}

-(void)scrollToPage:(int)page animated:(BOOL)animated
{
  int pageCount = self.pageCount;
  page = MAX(0, MIN(pageCount-1, page));
  
  NSLog(@"Scroll to page %d of %d", page+1, pageCount);
  
  CGPoint pos = ccp(-(viewSize.width * page), container.position.y);
  
  [self setContentOffset:pos animated:animated];
}

#pragma mark - Panning and zooming

- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated
{
  CGPoint oldPoint, min, max;
  CGFloat newX, newY;

  min = [self minContainerOffsetWithOvershot:CGPointZero];
  max = [self maxContainerOffsetWithOvershot:CGPointZero];

  oldPoint = container.position;
  newX     = MIN(offset.x, max.x);
  newX     = MAX(newX, min.x);
  newY     = MIN(offset.y, max.y);
  newY     = MAX(newY, min.y);
  
  CGPoint pos = ccp(newX, newY);
  
  if(animated){
    float duration = 0;
    if(direction == CCScrollLayerDirectionHorizontal)
      duration = fabsf(newX - oldPoint.x) / SCROLL_MAX_VELOCITY;
    else
      duration = fabsf(newY - oldPoint.y) / SCROLL_MAX_VELOCITY;
    
    isAnimating = YES;
    [container stopAllActions];
    [container runAction:[CCSequence actions:
                          [CCEaseOut actionWithAction:
                           [CCMoveTo actionWithDuration:duration position:pos]
                          rate:1.0]
                          ,
                          [CCCallFunc actionWithTarget:self selector:@selector(stoppedDecelerating:)],
                          nil]];
  }else{
    container.position = pos;
    [self stoppedDecelerating:nil];
  }
}


- (void)setZoomScale:(CGFloat)zoom animated:(BOOL)animated
{
	zoom = MIN(zoom, maximumZoom);
	zoom = MAX(zoom, minimumZoom);

	CGSize oldSize = [self contentSize];

	if(animated)
	{
    isAnimating = YES;
    
		if(zoomBouncing == NO && [delegate respondsToSelector:@selector(scrollLayerDidEndZooming:atScale:)])
			[delegate scrollLayerDidEndZooming:self atScale:zoom];

    [container stopAllActions];
		[container runAction:
		 [CCSequence actions:
		  [CCEaseSineInOut actionWithAction:[CCScaleTo actionWithDuration:BOUNCE_DURATION scale:zoom]],
		  [CCCallBlock actionWithBlock:^{ 
			 if(zoomBouncing && [delegate respondsToSelector:@selector(scrollLayerDidEndZooming:atScale:)])
				 [delegate scrollLayerDidEndZooming:self atScale:zoom];

			 zoomBouncing = NO;
		 }],
		  nil]];
	}
	else
	{
		container.scale = zoom;
	}

	CGSize newSize = CGSizeMake(zoom * container.contentSize.width, zoom * container.contentSize.height);
	CGSize deltaSize = CGSizeMake(oldSize.width - newSize.width, oldSize.height - newSize.height);
	CGPoint pointPercent = CGPointMake(lastGesturePoint.x / container.contentSize.width, lastGesturePoint.y / container.contentSize.height);
	container.position = ccpAdd(container.position, CGPointMake(deltaSize.width * pointPercent.x, deltaSize.height * pointPercent.y));
	[self setContentOffset:container.position animated:YES];
}


#pragma mark - Gesture recognizer actions

- (void)handlePanGesture:(UIPanGestureRecognizer *)gestureRecognizer
{
  NSTimeInterval now    = CFAbsoluteTimeGetCurrent();
  CGPoint newPoint      = [[CCDirector sharedDirector] convertToGL:[gestureRecognizer locationInView:[CCDirector sharedDirector].view]];
  
	switch(gestureRecognizer.state)
	{
		case UIGestureRecognizerStateBegan:
		{
      lastGestureTime       = now;
			lastGesturePoint      = newPoint;
      totalGestureTime      = 0;
      totalGestureDistance  = CGPointZero;
      scrollVelocity        = CGPointZero;
      isAnimating           = NO;
      [container stopAllActions];
			
			if([delegate respondsToSelector:@selector(scrollLayerWillBeginDragging:)])
				[delegate scrollLayerWillBeginDragging:self];
			
			break;
		}
			
		case UIGestureRecognizerStateChanged:
		{
      NSTimeInterval timeDiff = now - lastGestureTime;
      lastGestureTime         = now;
			
			CGPoint moveDistance    = ccpSub(newPoint, lastGesturePoint);
      lastGesturePoint        = newPoint;
			
      if(direction == CCScrollLayerDirectionHorizontal)
        moveDistance.y = 0;
      if(direction == CCScrollLayerDirectionVertical)
        moveDistance.x = 0;
      
      totalGestureTime        += timeDiff;
      totalGestureDistance    = ccpAdd(totalGestureDistance, moveDistance);
      
      scrollVelocity          = ccpMult(totalGestureDistance, 1.0/totalGestureTime);
      
      CGPoint newPos          = ccpAdd(container.position, moveDistance);
      
      CGPoint overshot        = (bounces)?ccp(OVERSHOOT_DISTANCE, OVERSHOOT_DISTANCE):CGPointZero;
      CGPoint clampPos        = [self clampedPosition:newPos withOvershot:overshot];
      
      container.position      = clampPos;
      
      [self scrollLayerDidScroll];
			
			break;
		}
			
		default:
		{
      decelerating            = YES;
      
      if([delegate respondsToSelector:@selector(scrollLayerWillBeginDecelerating:)])
        [delegate scrollLayerWillBeginDecelerating:self];
			
			if([delegate respondsToSelector:@selector(scrollLayerDidEndDragging:willDecelerate:)])
				[delegate scrollLayerDidEndDragging:self willDecelerate:YES];
			
			break;
		}
	}
}


- (void)handlePinchGesture:(UIPinchGestureRecognizer *)gestureRecognizer
{
	switch(gestureRecognizer.state)
	{
		case UIGestureRecognizerStateBegan:
		{
			gestureRecognizer.scale = container.scale;
			
			if([delegate respondsToSelector:@selector(scrollLayerWillBeginZooming:)])
				[delegate scrollLayerWillBeginZooming:self];
			
			break;
		}
			
		case UIGestureRecognizerStateChanged:
		{
			CGFloat zoomDistance = gestureRecognizer.scale;
			
			if(gestureRecognizer.scale > maximumZoom)
			{
				zoomDistance = (bouncesZoom) ? maximumZoom + ((gestureRecognizer.scale - maximumZoom) * 0.25f) : maximumZoom;
			}
			else if(gestureRecognizer.scale < minimumZoom)
			{
				zoomDistance = (bouncesZoom) ? minimumZoom - ((minimumZoom - gestureRecognizer.scale) * 0.25f) : minimumZoom;
			}
			
			lastGesturePoint = [container convertToNodeSpace:[[CCDirector sharedDirector] convertToGL:[gestureRecognizer locationInView:[CCDirector sharedDirector].view]]];
			CGSize oldSize = [self contentSize];
			
			container.scale = zoomDistance;
			
			CGSize newSize = [self contentSize];
			CGSize deltaSize = CGSizeMake(oldSize.width - newSize.width, oldSize.height - newSize.height);
			CGPoint pointPercent = CGPointMake(lastGesturePoint.x / container.contentSize.width, lastGesturePoint.y / container.contentSize.height);
			container.position = ccpAdd(container.position, CGPointMake(deltaSize.width * pointPercent.x, deltaSize.height * pointPercent.y));
			
			if([delegate respondsToSelector:@selector(scrollLayerDidZoom:)])
				[delegate scrollLayerDidZoom:self];
			
			break;
		}
			
		default:
		{
			zoomBouncing = YES;
			[self setZoomScale:container.scale animated:YES];
			
			break;
		}
	}
}

#pragma mark - Gesture delegate

// called when a gesture recognizer attempts to transition out of UIGestureRecognizerStatePossible. returning NO causes it to transition to UIGestureRecognizerStateFailed
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  if([delegate respondsToSelector:@selector(gestureRecognizerShouldBegin:)])
    return [delegate gestureRecognizerShouldBegin:gestureRecognizer];
  
  return YES;
}

// called when the recognition of one of gestureRecognizer or otherGestureRecognizer would be blocked by the other
// return YES to allow both to recognize simultaneously. the default implementation returns NO (by default no two gestures can be recognized simultaneously)
//
// note: returning YES is guaranteed to allow simultaneous recognition. returning NO is not guaranteed to prevent simultaneous recognition, as the other gesture's delegate may return YES
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  if([delegate respondsToSelector:@selector(gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:)])
    return [delegate gestureRecognizer:gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:otherGestureRecognizer];
  
  return NO;
}

// called before touchesBegan:withEvent: is called on the gesture recognizer for a new touch. return NO to prevent the gesture recognizer from seeing this touch
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
  if([delegate respondsToSelector:@selector(gestureRecognizer:shouldReceiveTouch:)])
    return [delegate gestureRecognizer:gestureRecognizer shouldReceiveTouch:touch];
  
  return NO;
}


#pragma mark - CCNode overrides

- (CGSize)contentSize
{
    return CGSizeMake(container.scaleX * container.contentSize.width, container.scaleY * container.contentSize.height); 
}


- (void)setContentSize:(CGSize)size
{
    container.contentSize = size;
}

// Make sure all children go to the container.
- (void)addChild:(CCNode *)node  z:(int)z tag:(int)aTag
{
  if(node == container){
    [super addChild:node z:z tag:aTag];
    return;
  }
  
  //TODO: is this necessary?
  node.ignoreAnchorPointForPosition = NO;
  node.anchorPoint = ccp(0.0f, 0.0f);

  [container addChild:node z:z tag:aTag];
}

-(CCNode*) getChildByTag:(NSInteger) aTag
{
	return [container getChildByTag:aTag];
}

@end
