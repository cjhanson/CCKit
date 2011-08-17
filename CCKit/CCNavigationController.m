//
//  CCNavigationController.m
//  Nuked
//
//  Created by Jerrod Putman on 8/12/11.
//  Copyright 2011 Tiny Tim Games. All rights reserved.
//

#import "CCNavigationController.h"


#define kSlideAnimationOffset 300.0f
#define kZoomAnimationOffset 0.5f

const float CCNavigationControllerAnimationDurationDefault = 0.35f;

typedef enum
{
	CCNavigationControllerAnimationDirectionPush,
	CCNavigationControllerAnimationDirectionPop,
	
} CCNavigationControllerAnimationDirection;





@implementation CCNavigationController
{
	NSMutableArray *nodeStack;
}

@synthesize animationStyle;
@synthesize animationDuration;
@synthesize delegate;


#pragma mark - Private

- (void)slideAnimationWithDirection:(CCNavigationControllerAnimationDirection)direction incomingNode:(CCNode<CCRGBAProtocol> *)incomingNode outgoingNode:(CCNode<CCRGBAProtocol> *)outgoingNode
{
	CGPoint moveByPosition = (direction == CCNavigationControllerAnimationDirectionPush) ? ccp(-kSlideAnimationOffset, 0) : ccp(kSlideAnimationOffset, 0);
	CGPoint incomingInitialPosition = ccpAdd(incomingNode.position, (direction == CCNavigationControllerAnimationDirectionPush) ? ccp(kSlideAnimationOffset, 0) : ccp(-kSlideAnimationOffset, 0));
	
	if(outgoingNode != nil)
	{
		CGPoint outgoingPreviousPosition = outgoingNode.position;
		
		[outgoingNode runAction:
		 [CCSequence actions:
		  [CCSpawn actions:
		   [CCEaseSineInOut actionWithAction:[CCMoveBy actionWithDuration:animationDuration position:moveByPosition]],
		   [CCFadeTo actionWithDuration:animationDuration opacity:0],
		   nil],
		  [CCCallBlock actionWithBlock:^{
			 if(outgoingNode != incomingNode)
				 [outgoingNode removeFromParentAndCleanup:(direction == CCNavigationControllerAnimationDirectionPop)];
			 outgoingNode.position = outgoingPreviousPosition;
		   }],
		  nil]
		 ];
	}
	
	incomingNode.position = incomingInitialPosition;
	incomingNode.opacity = 0;
	
	[incomingNode runAction:
	 [CCSequence actions:
	  [CCSpawn actions:
	   [CCEaseSineInOut actionWithAction:[CCMoveBy actionWithDuration:animationDuration position:moveByPosition]],
	   [CCFadeTo actionWithDuration:animationDuration opacity:255],
	   nil],
	  [CCCallBlock actionWithBlock:^{
		 if(delegate != nil
			&& [delegate respondsToSelector:@selector(navigationController:didShowNode:animated:)])
			 [delegate navigationController:self didShowNode:incomingNode animated:YES];
	   }],
	  nil]
	 ];
}


- (void)zoomAnimationWithDirection:(CCNavigationControllerAnimationDirection)direction incomingNode:(CCNode<CCRGBAProtocol> *)incomingNode outgoingNode:(CCNode<CCRGBAProtocol> *)outgoingNode
{
	float scaleToScale = (direction == CCNavigationControllerAnimationDirectionPush) ? kZoomAnimationOffset : -kZoomAnimationOffset;
	float incomingInitialScale = incomingNode.scale + ((direction == CCNavigationControllerAnimationDirectionPush) ? -kZoomAnimationOffset : kZoomAnimationOffset);
	
	outgoingNode.anchorPoint = CGPointZero;
	incomingNode.anchorPoint = CGPointZero;
	
	if(outgoingNode != nil)
	{
		float outgoingPreviousScale = outgoingNode.scale;
		
		[outgoingNode runAction:
		 [CCSequence actions:
		  [CCSpawn actions:
		   [CCEaseSineInOut actionWithAction:[CCScaleTo actionWithDuration:animationDuration scale:outgoingNode.scale + scaleToScale]],
		   [CCFadeTo actionWithDuration:animationDuration opacity:0],
		   nil],
		  [CCCallBlock actionWithBlock:^{
			 if(outgoingNode != incomingNode)
				 [outgoingNode removeFromParentAndCleanup:(direction == CCNavigationControllerAnimationDirectionPop)];
			 outgoingNode.scale = outgoingPreviousScale;
		   }],
		  nil]
		 ];
	}
	
	incomingNode.scale = incomingInitialScale;
	incomingNode.opacity = 0;
	
	[incomingNode runAction:
	 [CCSequence actions:
	  [CCSpawn actions:
	   [CCEaseSineInOut actionWithAction:[CCScaleTo actionWithDuration:animationDuration scale:1.0f]],
	   [CCFadeTo actionWithDuration:animationDuration opacity:255],
	   nil],
	  [CCCallBlock actionWithBlock:^{
		 if(delegate != nil
			&& [delegate respondsToSelector:@selector(navigationController:didShowNode:animated:)])
			 [delegate navigationController:self didShowNode:incomingNode animated:YES];
	   }],
	  nil
	  ]
	 ];
}


- (void)playTransitionAnimationWithDirection:(CCNavigationControllerAnimationDirection)direction incomingNode:(CCNode<CCRGBAProtocol> *)incomingNode outgoingNode:(CCNode<CCRGBAProtocol> *)outgoingNode
{
	switch(animationStyle)
	{
		case CCNavigationControllerAnimationStyleSlide:
			[self slideAnimationWithDirection:direction incomingNode:incomingNode outgoingNode:outgoingNode];
			break;
			
		case CCNavigationControllerAnimationStyleZoom:
			[self zoomAnimationWithDirection:direction incomingNode:incomingNode outgoingNode:outgoingNode];
			break;

		default:
			if(delegate != nil
			   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
				[delegate navigationController:self willShowNode:incomingNode animated:NO];
			break;
	}
}


#pragma mark - Creating the navigation controller

- (id)initWithRootNode:(CCNode<CCRGBAProtocol> *)node
{
	if((self = [super init]))
	{
		nodeStack = [[NSMutableArray alloc] initWithCapacity:3];
		
		animationStyle = CCNavigationControllerAnimationStyleDefault;
		animationDuration = CCNavigationControllerAnimationDurationDefault;
		
		[self pushNode:node animated:NO];
	}
	
	return self;
}


#pragma mark - Accessing items on the navigation stack

- (CCNode<CCRGBAProtocol> *)topNode
{
	return [nodeStack lastObject];
}


- (NSArray *)nodes
{
	return [NSArray arrayWithArray:nodeStack];
}


- (void)setNodes:(NSArray *)nodes
{
	nodeStack = [NSMutableArray arrayWithArray:nodes];
}


- (void)setNodes:(NSArray *)nodes animated:(BOOL)animated
{
	CCNode<CCRGBAProtocol> *oldTop = self.topNode;
	CCNode<CCRGBAProtocol> *newTop = [nodes lastObject];
	
	if(delegate != nil
	   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
		[delegate navigationController:self willShowNode:newTop animated:animated];

	self.nodes = nodes;
	[self addChild:newTop];
	newTop.opacity = 255;
	
	if(animated)
	{
		// TODO: Determine the proper direction of the transition.
		[self playTransitionAnimationWithDirection:CCNavigationControllerAnimationDirectionPush incomingNode:newTop outgoingNode:oldTop];
	}
	else
	{
		[oldTop removeFromParentAndCleanup:YES];
		if(delegate != nil
		   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
			[delegate navigationController:self willShowNode:newTop animated:NO];
	}
}


#pragma mark - Pushing and popping stack items

- (void)pushNode:(CCNode<CCRGBAProtocol> *)node animated:(BOOL)animated
{
	CCNode<CCRGBAProtocol> *oldTop = self.topNode;
	CCNode<CCRGBAProtocol> *newTop = node;
	
	if(delegate != nil
	   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
		[delegate navigationController:self willShowNode:newTop animated:animated];
	
	[nodeStack addObject:newTop];
	[self addChild:node];
	node.opacity = 255;
	
	if(animated)
	{
		[self playTransitionAnimationWithDirection:CCNavigationControllerAnimationDirectionPush incomingNode:newTop outgoingNode:oldTop];
	}
	else
	{
		if(oldTop != nil)
			[oldTop removeFromParentAndCleanup:NO];

		if(delegate != nil
		   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
			[delegate navigationController:self willShowNode:newTop animated:NO];
	}
}


- (CCNode *)popNodeAnimated:(BOOL)animated
{
	if([nodeStack count] <= 1)
		return nil;
	
	CCNode<CCRGBAProtocol> *oldTop = self.topNode;
	[nodeStack removeLastObject];
	CCNode<CCRGBAProtocol> *newTop = self.topNode;
	
	if(delegate != nil
	   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
		[delegate navigationController:self willShowNode:newTop animated:animated];
	
	[self addChild:newTop];
	newTop.opacity = 255;

	if(animated)
	{
		[self playTransitionAnimationWithDirection:CCNavigationControllerAnimationDirectionPop incomingNode:newTop outgoingNode:oldTop];
	}
	else
	{
		if(oldTop != nil)
			[oldTop removeFromParentAndCleanup:YES];
		
		if(delegate != nil
		   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
			[delegate navigationController:self willShowNode:newTop animated:NO];
	}
	
	return oldTop;
}


- (NSArray *)popToRootAnimated:(BOOL)animated
{
	CCNode<CCRGBAProtocol> *oldTop = self.topNode;
	CCNode<CCRGBAProtocol> *newTop = [nodeStack objectAtIndex:0];
	
	if(oldTop == newTop)
		return nil;
	
	if(delegate != nil
	   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
		[delegate navigationController:self willShowNode:newTop animated:animated];
	
	[self addChild:newTop];
	newTop.opacity = 255;

	NSMutableArray *oldArray = nodeStack;
	[oldArray removeObjectAtIndex:0];
	
	nodeStack = [NSMutableArray arrayWithObject:newTop];
	
	if(animated)
	{
		[self playTransitionAnimationWithDirection:CCNavigationControllerAnimationDirectionPop incomingNode:newTop outgoingNode:oldTop];
	}
	else
	{
		if(oldTop != nil)
			[oldTop removeFromParentAndCleanup:YES];
		
		if(delegate != nil
		   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
			[delegate navigationController:self willShowNode:newTop animated:NO];
	}
	
	return [NSArray arrayWithArray:oldArray];
}


- (NSArray *)popToNode:(CCNode<CCRGBAProtocol> *)node animated:(BOOL)animated
{
	if(![nodeStack containsObject:node]
	   || [nodeStack count] <= 1)
		return nil;
	
	NSInteger oldTopIndex = [nodeStack indexOfObject:node];
	NSInteger newTopIndex = oldTopIndex - 1;
	
	CCNode<CCRGBAProtocol> *oldTop = node;
	CCNode<CCRGBAProtocol> *newTop = [nodeStack objectAtIndex:newTopIndex];
	
	if(oldTop == newTop)
		return nil;
	
	if(delegate != nil
	   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
		[delegate navigationController:self willShowNode:newTop animated:animated];
	
	[self addChild:newTop];
	newTop.opacity = 255;

	NSRange range = { oldTopIndex, [nodeStack count] - oldTopIndex };
	NSArray *removedArray = [nodeStack subarrayWithRange:range];
	[nodeStack removeObjectsInRange:range];
	
	if(animated)
	{
		[self playTransitionAnimationWithDirection:CCNavigationControllerAnimationDirectionPop incomingNode:newTop outgoingNode:oldTop];
	}
	else
	{
		if(oldTop != nil)
			[oldTop removeFromParentAndCleanup:YES];
		
		if(delegate != nil
		   && [delegate respondsToSelector:@selector(navigationController:willShowNode:animated:)])
			[delegate navigationController:self willShowNode:newTop animated:NO];
	}
	
	return removedArray;
}


@end


#pragma mark -


@implementation CCNode (NavigationControllerAdditions)

- (CCNavigationController *)navigationController
{
	if([self.parent isKindOfClass:[CCNavigationController class]])
		return (CCNavigationController *)self.parent;
	
	return nil;
}

@end

